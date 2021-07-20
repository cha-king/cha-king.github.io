FROM debian

RUN apt update
RUN apt upgrade -y
RUN apt install -y ruby-full build-essential zlib1g-dev

RUN gem install jekyll bundler

COPY ./Gemfile ./Gemfile
COPY ./Gemfile.lock ./Gemfile.lock

RUN bundle install

WORKDIR /app

EXPOSE 4000

CMD ["bundle", "exec", "jekyll", "serve", "--host=0.0.0.0"]
