---
layout: post
title:  "Ableton Live - Prophet 6 - NRPN Issues"
date:   2020-10-27 21:59:00 -0700
tags: max/msp music ableton
---
About a year ago, I splurged and bought myself a Prophet 6 synthesizer and, 
to this day, I'm still loving it.

<img src='/assets/images/prophet-6/prophet.jpg'>

I try to integrate my music equipment with Ableton Live as much as possible
and, for the most part, the Prophet 6 has shown no issue here. There was, 
however, something I've come across in doing so that exhibited some rather
annoying behavior.

## The issue
In my current setup, I have the Prophet 6 both sending and receiving MIDI from
Ableton. This would ordinarily cause issues with MIDI feedback, so I disable local
control on the Prophet 6 in order to work around this. The benefit of this approach is
that, in addition to the recorded audio, I can record any notes played as well as any
parameter changes on the synth. This makes it easy for me to go back and tweak things
after the fact without having to re-record everything. And when I do finally re-record
to audio, I can just play back the MIDI that was recorded. So far so good.

The issue I found though, is that everytime I played back any MIDI notes recorded from
the Prophet, they'd be transposed down by what sounded like three octaves or so.

It's definitely pretty annoying to record a synth loop only to hear it pitched 
down immediately on playback.

## The cause
Digging further, I first tried to figure out what was actually pitching everything down.
The MIDI notes that were recorded hadn't changed, and they appeared fine within Ableton.
Then, oddly enough, I realized that anything I played after the fact would also be pitched
down. All I knew was that playing back recorded MIDI is what triggered this.

Ultimately, I discovered that the pitch decrease was coming from the main oscillator being
inexplicitly tuned down to it's minimum setting. I could manually restore it, but playing
back any MIDI would always force it back down.

From initially setting up the prophet, I knew that the MIDI usage strays from more typical 
MIDI CC values, instead using Non-Registered Parameter Number (NRPN) values. I haven't 
dealt with these much, but I do know that they provide a much higher granularity for parameter 
change, 14-bit, I believe, rather than MIDI CC's relatively infamous 7-bit granularity. Maybe this
was related.

I dug out the manual and flipped to the parameter spec for NRPN

<img src='/assets/images/prophet-6/nrpn.png'>

Interestingly enough, the first value listed at NRPN 0 was the exact value I was having issues
with: oscillator frequency. This didn't seem like coincidence to me.

Looking into it, I was able to see that Ableton doesn't really have first-class support
for NRPN beyond just capturing it in MIDI CC format. For the most part, this works fine,
since Ableton will just play this back to the Prophet, which known how to interpret it. 
Looking at the recorded CC data though, I was able to see where the problem is.

<img src='/assets/images/prophet-6/midi.png'>

Due to the nature of Ableton's MIDI CC automation, whenever a MIDI clip started playing, CC values equating to NRPN (0,0) were
being trasmit as the clip automation restart. For typical CC values, this makes sense, since 
you'd ordinarily want the clip's MIDI values returning to their initial state when a clip
starts again.

With NRPN data, however, we don't want this. Ordinarily, the values you're seeing would map directly
to the single parameter on the Prophet, but in the case of NRPN, it depends on another
separate CC value as well. As a result, the value of (0,0) was setting the oscillator
frequency to its minimum value whenever a clip with any CC automation played back.

## The solution
The initial solution that came to mind here was to configure the Prophet to both transmit and
receive more typical MIDI CC values rather than NRPN. This would allow for Ableton to 
handle these values a little more gracefully. I wasn't incredibly happy with this though.
Reading the manual, NRPN is recommended, and for good reason. Truthfully, the 7-bit precision
of MIDI CC is actually noticeably low, and I'd hate to compromise here for.

Instead, I decided I would write a quick Max for Live patch that would filter out these
problematic NRPN values that Ableton was trasmitting. The implication here is that I'll
never legitimately be able to send those values, although I don't think I'll need
to detune my oscillator so low ordinarily anyway.

As a side note, my favorite thing about Max/MSP being directly integrated within Ableton
Live like this is that it allows for relatively simple little hacks like this without
any durastic changes to Ableton. Actually, this is essentially what the first software I
ever wrote was! More on that later..

But anyway, here's the patch I threw together

<img src='/assets/images/prophet-6/rack.png'>

Ordinarily I'd keep this collapsed and hidden but I obviously kept it expanded here to demonstrate.
A bit of extra context, the leftmost device is a little M4L patch I wrote for saving and replaying
Sysex data to the Prophet for managing patches myself. On the right is the External Audio Effect
for the synth itself.

Essentially the patch is just looking for that specific NRPN value and omitting it from 
the MIDI output. Then, I go ahead and forward all non-CC MIDI data to ensure that everything
else works properly.

Easy.

## Final thoughts
Glad I got this fixed, since this has actually been giving me some issues for a bit! This actually
caused a lot of worry before, as I was afraid that whatever was happening was doing more alteration
to my Prophet patches, but it makes sense that only oscillator frequency was affected. Since putting
this into use, I've been having no more issues there.

The Max for Live patch is [available here for download](/assets/files/prophet-6/NRPN Filter.amxd) in the case that you've
been seeing this issue yourself. To install, just plop it in your 'Max MIDI Effect' folder in your
Ableton library and throw it anywhere before the Prophet in your MIDI chain.

Hope it comes in handy!
