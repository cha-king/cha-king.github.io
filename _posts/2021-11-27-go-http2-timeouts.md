---
layout: post
title: "Improving HTTP timeouts in Golang"
tags: golang go http http2
---

I've been working a lot with Golang (aka Go) lately, particularly its [HTTP library](https://pkg.go.dev/net/http).

Like many other libraries, you have to be careful about the default parameters and objects that are included. Oftentimes 
these are more catered towards getting you up and running than providing the most sensible configuration for running
in production.

Most of the time, for instance, you're going to want to add timeouts to your HTTP requests. Otherwise, in the case that something
goes wrong with your connection, you'll find your code blocking forever and bringing your application to a halt. Given that timeout
values like this will generally be specific to your application, and there's no catch-all value to be used, it makes sense that
these libraries leave it to the developer to specify these values. Still, inevitably, people will forget to read further into
documentation, and forget to set these values properly, leading to plenty of articles [like this one](https://medium.com/@nate510/don-t-use-go-s-default-http-client-4804cb19f779) to help out.

Until recently, I liked to think that I was on top of this and was doing my due diligence to handle HTTP timeouts properly. Turns out, I was wrong! It also turns out that several others have made the same mistakes I did, so I figured I'd do a quick write-up on the matter.

But first, a bit of context on my part..

# Background
For a project I'm currently working on, I'm working with devices in a relatively unstable network environment. In the event that
a device is unable to connect to our servers, we want to be able to catch and handle this gracefully, ideally as soon as possible.

I won't get too into the details, but in our case, we just needed to create a new connection to the server in the event that something went wrong. This is a pretty common use case though. Something's not working as expected, so you timeout and try again.

This seems pretty straightforward, so long as we take the above into account and make sure we're adding a proper timeout to our HTTP client. Unfortunately though, there was more to it..

# The issue
As mentioned above, you'd think we'd be handling this properly by configuring out HTTP client with a timeout as we did below:

```go
httpClient := &http.Client{
    Timeout: 10 * time.Second,
}
```

Unfortunately, even with this timeout in place, we were having lots of issues.

The app I was working with included some websocket connections in addition to the HTTP client. For the websocket connections, our 
timeouts were working as expected. After the configured time has passed, the client would kill the connection and create a new 
connection to our server, and we were able to observe that the websockets were continuing to function properly in our app.

With the HTTP client, however, we were able to see that the requests were timing out after 10 seconds, but even though the websockets
were able to talk over the network just fine, the HTTP client would continue to fail, always timing out after 10 seconds.

This was quite confusing. Why was the HTTP client continuing to fail while the the websockets were doing just fine?

Well, there was something I mentioned earlier that's actually pretty crucial here. As I mentioned, for my use case, in the event that 
something went wrong, we needed to **create a new connection** to the server.

# Connection pooling
Investigating the issue further, I used `netstat` to get a sense for what was happening with the application's TCP connections under
the hood.

I was able to see that, after the timeout elapsed, the websockets were creating an entirely new TCP connection to our servers, whereas
the HTTPS client over port 443 was persisting and continuing to try and use a connection / network route that we knew would fail.

This is partially a result of functionality formally introduced with HTTP/1.1 known as [HTTP persistent connection](https://en.wikipedia.org/wiki/HTTP_persistent_connection).

Generally, it makes a lot of sense. Nowadays, it's common to make frequent and subsequent HTTP requests so, rather than dealing with the additional overhead of creating a new TCP connection per request, you can simply reuse the connection.

What I found though is that these connections are *much* more persistent than I actually anticipated.

# TCP Keepalive
So HTTP was going to re-use the initial connection. I could disable this functionality altogether, and force the client to create
a new connection on each request, but this is really non-ideal and adds a lot of overhead.

This shouldn't be an issue though, right? [TCP Keepalive](https://tldp.org/HOWTO/TCP-Keepalive-HOWTO/overview.html) exists to catch dead connections, and we can just rely on the operating system to handle this for us.

Already, I could tell that the connection wasn't being re-established with the timeout I provided, so maybe there was more 
configuration needed to tune the Keepalive. Looking at Go's default HTTP transport though, it seems as though these are already in place:
```go
var DefaultTransport RoundTripper = &Transport{
	Proxy: ProxyFromEnvironment,
	DialContext: (&net.Dialer{
		Timeout:   30 * time.Second,
		KeepAlive: 30 * time.Second,
	}).DialContext,
	ForceAttemptHTTP2:     true,
	MaxIdleConns:          100,
	IdleConnTimeout:       90 * time.Second,
	TLSHandshakeTimeout:   10 * time.Second,
	ExpectContinueTimeout: 1 * time.Second,
}
```
After playing around with these values rather haphazardly though, I still had lots of issues getting the bad connection to timeout.
With these settings, I was waiting upwards of 10 minutes and still not seeing any new connections created. 

Digging around, it turns out I'm not alone in my confusion here. I found 
[several](https://github.com/golang/go/issues/40201)
[Github](https://github.com/golang/go/issues/33515)
[issues](https://github.com/golang/go/issues/28012)
[where](https://github.com/golang/go/issues/36026)
others were having the same issue as me.

The first piece of important information that came out of this was that **TCP Keepalive takes forever by default**. (not literally)

Seriously.

If using Linux's default configuration, it can take roughly **two hours** before a dead connection is killed by the OS.

Granted, Go's implementation changes some of these defaults a bit, but [this really useful comment](https://github.com/golang/go/issues/33515#issuecomment-520132069) by Github user odeke-em computes that the timeout should be taking **nine minutes**.

To quote him:
>...if you use the default one in the default transport, please expect it to be >=9 minutes given that maths on its behavior.
This could perhaps be the subject of blogpost since this is an esoteric topic that doesn't have much literature out there.

This is generally a lot slower than what I'd need, but seeing defaults like these also tells me that perhaps I'm just using the wrong tool for the job. Also, I never fully understood why, but timing out seemed to be taking longer than 9 minutes for me. 

Additionally, websockets sit on top of TCP, so why do my websocket connections not seem to be having this issue?

# Application-layer timeouts
As I've alluded to, maybe I'm not using the right tool for the job..

To answer my previous question, the websockets were acting as desired because their timeout is implemented at the application layer 
through [PING](https://datatracker.ietf.org/doc/html/rfc6455#section-5.5.2) and [PONG](https://datatracker.ietf.org/doc/html/rfc6455#section-5.5.3) frames.

As I learned through the above Github issues, HTTP/2 actually features its own [application-layer ping](https://datatracker.ietf.org/doc/html/rfc7540#section-6.7). This seems like a much better tool for the job, but how do we actually use it?

To my surprise, this functionality isn't actually provided through Go's HTTP library. To use it, you need to resort to the external
[http2](https://pkg.go.dev/golang.org/x/net/http2) package. In there, you can utilize the `ReadIdleTimeout` and `PingTimeout`
parameters to create an extended HTTP transport to use with the initial client.

Ultimately, my client's configuration looks as follows:
```go
httpClient := &http.Client{
    Timeout: 10 * time.Second,
    Transport: &http2.Transport{
        ReadIdleTimeout: 10 * time.Second,
        PingTimeout:     10 * time.Second,
    },
}
```
Here, after 10 seconds of inactivity, a ping frame will be sent with a 10 second timeout. If no response is heard in that time,
a new connection will be created.

Testing this out, it worked! Finally my issue was solved, although it took me *way* too long to end up here.

# Wrapping up
In finding my way to this solution, I was pretty surprised to find that this behavior wasn't configured by default, and was more 
surprised at how convoluted the path was to wind up at a good solution. This being the case, I figured I'd do this write-up in the 
hopes that it might prove useful to anyone else in the same situation.

So, hope it helps! Thanks for sticking with me if you made it this far.
