#!/usr/bin/env ruby

# frozen_string_literal: true

require 'json'
require 'net/http'
require 'nokogiri'
require 'time'


INDEX = 'https://www.jaza.jp/search-enkan'


def check(uri, redirect_limit)
  STDERR.puts "GET #{uri}"

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    # 本来は HEAD を使いたいところだが、登別マリンパークニクスで正しく動作しないので GET を使う
    res = http.request_get(uri)
    case res
    when Net::HTTPSuccess
      uri
    when Net::HTTPRedirection
      raise if redirect_limit == 0
      resolve(uri + res['Location'], redirect_limit: redirect_limit - 1)
    end
  end
end

##
# `uri` のリダイレクトを解決する。また、可能なら HTTPS にアップグレードする。
def resolve(uri, redirect_limit: 5)
  if uri.scheme == 'https'
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      check(uri, redirect_limit)
    end
  else
    https = uri.clone
    https.scheme = 'https'
    https = URI(https.to_s)
    # XXX: inline rescue やめたい
    (check(https, redirect_limit) rescue nil) || check(uri, redirect_limit)
  end
end


timestamp = Time.now.utc.iso8601
html = Net::HTTP.get(URI(INDEX))
html = Nokogiri::HTML(html)

list = html.css('.enkan-list').map do |elm|
  elm.css('a').first
end.compact

STDERR.puts "Found #{list.length} institutions"

list.map! do |a|
  name = a.css('img').first.attribute('alt').value
  link = a.attribute('href').value
  Thread.new do
    resolved = resolve(URI(link)) rescue nil
    { name: name, link: link, resolved: resolved }
  end
end
list.map!(&:value)

puts(JSON.pretty_generate({ retrieved: timestamp, institutions: list }))
