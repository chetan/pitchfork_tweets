#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

require 'simple-rss'
require 'open-uri'
require 'scrapi'
require 'yaml'
require 'bitly'
require 'twitter'

CONF_FILE = File.join(File.expand_path(File.dirname(__FILE__)), "conf.yaml")
SAVE_FILE = File.join(File.expand_path(File.dirname(__FILE__)), "pf-save.txt")
URL = "http://feeds2.feedburner.com/PitchforkAlbumReviews"

# load config
config = YAML.load(File.read(CONF_FILE))

# load saved timestamp
newest = 0
if File.exists? SAVE_FILE then
  newest = File.read(SAVE_FILE).strip.to_i
end

# setup bitly
Bitly.use_api_version_3
bitly = Bitly.new(config["bitly_user"], config["bitly_key"])

# setup twitter
Twitter.configure do |c|
  c.consumer_key       = config["consumer_key"]
  c.consumer_secret    = config["consumer_secret"]
  c.oauth_token        = config["access_token"]
  c.oauth_token_secret = config["access_token_secret"]
end

# setup scrapi
score_scraper = Scraper.define do
  process "span.score", :score => :text
  process "div.bnm-label", :label => :text
  result :score, :label
end

# process rss feed
rss = SimpleRSS.parse(open(URL))
rss.items.reverse.each do |item|
  title = item[:title]
  date = item[:pubDate]
  link = item[:feedburner_origLink]

  next if date.to_i <= newest
  newest = date.to_i

  ret = score_scraper.scrape(URI.parse(link))
  if not ret.score then
    # TODO error
    puts "error scraping score from #{link}"
    next
  end
  score = ret.score.strip
  label = ret.label.strip

  short_url = bitly.shorten(link).short_url || link
  short_url.gsub!(%r{^http://}, '') # strip http:// to save some chars

  s = "#{title} (#{score}"
  s += ", #{label}" if not (label.nil? || label.empty?)
  s += ")"

  r = 140-s.length
  if r > short_url.length then
    s += " #{short_url}"
  elsif r == short_url.length then
    s += short_url
  else
    puts "not enough space for short_url:"
    puts s
  end

  # tweet it
  Twitter.update(s)
end

File.open(SAVE_FILE, 'w') { |f| f.write(newest) }