#!/usr/bin/env ruby

# frozen_string_literal: true

require 'curb'
require 'json'
require 'nokogiri'
require 'time'
require 'uri'


INDEX = 'https://www.jaza.jp/search-enkan'


def check(uri, redirect_limit)
  STDERR.puts "> GET #{uri}"

  # 本来は HEAD を使いたいところだが、登別マリンパークニクスで正しく動作しないので GET を使う
  curl = Curl.get(uri)
  status = curl.status
  STDERR.puts "< #{status}"
  case status[0]
  when '2'
    uri
  when '3'
    if redirect_limit == 0
      STDERR.puts 'Reached redirect limit'
      return
    end

    location = nil
    curl.header_str.split("\r\n") do |line|
      if match = line.match(/^Location: (.*)/i)
        STDERR.puts "< #{line}"
        location = match[1]
        break
      end
    end
    return unless location

    uri = (URI(uri) + location).to_s
    resolve(uri, redirect_limit: redirect_limit - 1)
  end
end

##
# `uri` のリダイレクトを解決する。また、可能なら HTTPS にアップグレードする。
def resolve(uri, redirect_limit: 5)
  if uri.start_with?('https://')
    check(uri, redirect_limit)
  elsif uri.start_with?('http://')
    https = uri.gsub(/^http/, 'https')
    begin
      # まずは HTTPS で試行
      check(https, redirect_limit)
    rescue Curl::Err::CurlError
      # HTTP にフォールバック
      check(uri, redirect_limit)
    end
  end
end


timestamp = Time.now.utc.iso8601
html = Curl.get(INDEX).body_str
html = Nokogiri::HTML(html)

list = html.css('.enkan-list').map do |elm|
  elm.css('a').first
end.compact

STDERR.puts "Found #{list.length} institutions"

list.map! do |a|
  name = a.css('img').first.attribute('alt').value
  link = a.attribute('href').value
  Thread.new do
    resolved = begin
      resolve(link)
    rescue Curl::Err::CurlError
      nil
    end
    { name: name, link: link, resolved: resolved }
  end
end
list.map!(&:value)

puts(JSON.pretty_generate({ retrieved: timestamp, institutions: list }))
