#!/usr/bin/env ruby

# frozen_string_literal: true

require 'English'
require 'filemagic'
require 'httparty'
require 'octokit'
require 'rouge'
require 'tempfile'
require 'tmpdir'
require 'watir'

# This script obtains a random file from a random GitHub repo. Due to the
# entropic nature of what we're doing, a variety of things can go wrong if we
# happen to get a repo or a file that isn't exactly what we expect. When we
# encounter this, we can raise this custom error to signal that we should try
# again with a different repo.
class BadExampleError < StandardError; end

GITHUB_TOKEN = ENV['GITHUB_TOKEN'] or raise 'GITHUB_TOKEN environment variable not set.'

GITHUB_CLIENT = Octokit::Client.new(access_token: GITHUB_TOKEN)

# This is an approximation of the number of total GitHub repositories, obtained
# by running a script in this repo, `bin/find-recent-github-repos`.
#
# The script tries to get close to the total number of repositories by fetching
# repositories at random by ID number and stopping when it's reached numbers
# high enough that the GitHub API is consistently returning 404.
#
# `generate-wallpaper.rb` will only fetch repos created through the date below.
# We can periodically re-run `bin/find-recent-github-repos` to get a new
# approximate repo count and update MAX_REPO_ID in order to fetch repos created
# more recently.
#
# Last updated: 2024-12-28
MAX_REPO_ID = 889_000_000

def random_repo
  GITHUB_CLIENT.repo rand(MAX_REPO_ID)

  # Some repos 404, I assume because they're private or have been deleted.
  # When we find a missing one, we try again.
rescue Octokit::NotFound
  random_repo
end

TMPDIR = Dir.mktmpdir
at_exit { FileUtils.remove_entry TMPDIR }

def download_archive(repo)
  tarball_url = GITHUB_CLIENT.archive_link repo[:full_name]

  tmpfile = Tempfile.new('archive_tarball', TMPDIR)
  File.open(tmpfile, 'wb') do |f|
    data = HTTParty.get(tarball_url).body
    f.write data
  end

  tmpfile
end

def random_archive
  repo = random_repo
  { repo: repo.full_name, tarball: download_archive(repo) }
end

def binary?(filename)
  fm = FileMagic.new(FileMagic::MAGIC_MIME)
  fm.file(filename) !~ %r{^text/}
ensure
  fm.close
end

def files_in_tarball(tarball)
  output = `tar tzf #{tarball.path} | grep -e '[^/]$' 2>/dev/null`
  raise BadExampleError, 'Bad tarball.' unless $CHILD_STATUS.exitstatus.zero?

  files_in_tarball = output.lines
  raise BadExampleError, 'No files in tarball.' if files_in_tarball.empty?

  output.lines
end

def extract_file_from_tarball!(tarball, filename)
  `tar xvf #{tarball.path} -C #{TMPDIR} #{filename} 2>/dev/null`
  raise BadExampleError, 'Bad tarball.' unless $CHILD_STATUS.exitstatus.zero?

  # Return the full path to the file.
  File.join TMPDIR, filename
end

# Given a file path, returns a tuple of two values:
# * A boolean indicating whether the file is usable
# * (optional) If it isn't usable, a string explaining why not
def usable?(file_path)
  if binary?(file_path)
    [false, 'File is binary']
  elsif file_path =~ /README|gitignore|gitattributes|npmignore|min\.js/
    [false, 'File too boring']
  else
    [true]
  end
end

def extract_random_file(tarball)
  files_in_tarball = files_in_tarball(tarball)

  (1..5).each do |attempt|
    random_file = files_in_tarball.sample.chomp
    file_path = extract_file_from_tarball!(tarball, random_file)
    usable, reason = usable?(file_path)
    return file_path if usable

    warn "Attempt ##{attempt} failed: #{reason}"
  end

  raise BadExampleError, "Couldn't find a usable file in tarball."
end

def random_file_in_random_repo
  (1..100).each do |attempt|
    repo, tarball = random_archive.values_at :repo, :tarball
    return { repo: repo, filename: extract_random_file(tarball) }
  rescue BadExampleError => e
    warn "Attempt ##{attempt} failed: #{e}"
  end
end

def rouge_html(source_code, filename)
  lexer = Rouge::Lexer.guess(source: source_code, filename: filename)
  formatter = Rouge::Formatters::HTML.new
  formatter.format(lexer.lex(source_code))
rescue Rouge::Guesser::Ambiguous, ArgumentError
  raise BadExampleError, 'Unable to detect filetype for syntax highlighting.'
end

def random_theme_css
  random_theme = Rouge::Theme.registry.values.sample
  random_theme.render(scope: 'body')
end

def format_code(filename)
  File.open filename do |file|
    file.sync = true
    source_code = file.read
    raise BadExampleError, 'Source file is empty.' if source_code =~ /^\s*$/

    { html: rouge_html(source_code, filename), css: random_theme_css }
  end
end

# Collected manually on 12/16/17.
MONOSPACE_GOOGLE_FONTS = [
  'Anonymous Pro',
  'Cousine',
  'Cutive Mono',
  'Fira Mono',
  'Inconsolata',
  'Nova Mono',
  'Overpass Mono',
  'Oxygen Mono',
  'PT Mono',
  'Roboto Mono',
  'Share Tech Mono',
  'Source Code Pro',
  'Space Mono',
  'Ubuntu Mono',
  'VT323'
].freeze

# rubocop:disable Style/MethodLength
def code_view(filename)
  html, css = format_code(filename).values_at(:html, :css)
  font = MONOSPACE_GOOGLE_FONTS.sample
  font_link = "https://fonts.googleapis.com/css?family=#{font.gsub ' ', '+'}"

  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <title>code view</title>
    <link href="#{font_link}" rel="stylesheet">
    <style type="text/css">
    pre { font-family: '#{font}', monospace; font-size: 3em; }
    #{css}
    </style>
    </head>
    <body>
      <pre>#{html}</pre>
    </body>
    </html>
  HTML
end
# rubocop:enable Style/MethodLength

def random_code_view
  attempt = 1

  while attempt <= 100
    begin
      repo, filename = random_file_in_random_repo.values_at :repo, :filename
      return { repo: repo, filename: filename, html: code_view(filename) }
    rescue BadExampleError => e
      warn "Attempt ##{attempt} failed: #{e}"
      attempt += 1
    end
  end
end

def with_browser(&block)
  opts = { args: ['--hide-scrollbars'] }
  browser = Watir::Browser.new :chrome, headless: true, options: opts
  block.call(browser)
ensure
  if browser.nil?
    warn '`browser` is nil. huh?'
  else
    browser.quit
  end
end

def assert_code_view_page!(browser)
  raise "File not found: #{in_html}" unless browser.title == 'code view'
end

# Uses `xrandr` to determine the screen resolution of the machine running this
# script.
def xrandr_screen_resolution
  `xrandr`.scan(/current (\d+) x (\d+)/).flatten.map(&:to_i)
end

# Scrolls down to a random position (Y coordinate) on the page.
def scroll_to_random_position!(browser, screen_height)
  x = 0
  y = Random.rand 0..[browser.body.height / 2 - screen_height, 0].max
  browser.scroll.to [x, y]
end

def random_screenshot(in_html, out_png)
  with_browser do |browser|
    browser.goto "file://#{in_html}"
    assert_code_view_page! browser

    width, height = xrandr_screen_resolution

    # Maximize the window to fullscreen.
    browser.window.resize_to width, height

    # Wait until the `pre` element is rendered before taking a screenshot.
    #
    # NB: I tried: browser.pre.wait_until_present
    #         and: browser.pre.wait_until {|pre| !pre.text.empty?}
    #
    #     but neither of these seemed to do the trick. The screenshot was still
    #     being taken before the code was being rendered in the `pre` element.
    #     In cases where there was a lot of code, this resulted in an empty
    #     screenshot.
    #
    #     Hard-coding a sleep of 5 seconds is not an ideal solution, but it gets
    #     the job done.
    sleep 5

    scroll_to_random_position! browser, height

    browser.screenshot.save(out_png)
  end
end

if __FILE__ == $PROGRAM_NAME
  File.open(Tempfile.new(['code_view', '.html'], TMPDIR), 'wb') do |file|
    html, repo, filename = random_code_view.values_at :html, :repo, :filename
    timestamp = Time.now.strftime '%Y%m%d%H%M%S'
    basename = File.basename filename
    out_file = "#{timestamp}-#{repo}-#{basename}.png".gsub '/', '-'
    file.sync = true
    file.write html
    random_screenshot file.path, out_file
    puts out_file
  end
end
