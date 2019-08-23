#!/usr/bin/env ruby

require 'filemagic'
require 'httparty'
require 'octokit'
require 'rouge'
require 'tempfile'
require 'tmpdir'
require 'watir'
require 'watir-scroll'

# This script obtains a random file from a random GitHub repo. Due to the
# entropic nature of what we're doing, a variety of things can go wrong if we
# happen to get a repo or a file that isn't exactly what we expect. When we
# encounter this, we can raise this custom error to signal that we should try
# again with a different repo.
class BadExampleError < StandardError; end

GITHUB_TOKEN = ENV['GITHUB_TOKEN'] or raise 'GITHUB_TOKEN environment variable not set.'

$github = Octokit::Client.new(:access_token => GITHUB_TOKEN)

# NB: I did some exploratory testing via the GitHub API on 12/12/17 and at that
# time, there were between 114 and 115 million GitHub repository IDs.
#
# That will be plenty to keep us busy for now. If we ever want to include
# repositories created after 12/12/2017, we can test some more and determine the
# updated count.
MAX_REPO_ID = 114_000_000

def random_repo
  $github.repo rand(MAX_REPO_ID)

  # Some repos 404, I assume because they're private or have been deleted.
  # When we find a missing one, we try again.
rescue Octokit::NotFound
  random_repo
end

$tmpdir = nil

def tmpdir
  if $tmpdir.nil?
    msg = "No tmpdir established; wrap your code in with_tmpdir."
    raise StandardError.new(msg)
  end
  $tmpdir
end

def with_tmpdir
  Dir.mktmpdir do |tmpdir|
    $tmpdir = tmpdir
    yield
    $tmpdir = nil
  end
end

def download_archive(repo)
  tarball_url = $github.archive_link repo[:full_name]

  tmpfile = Tempfile.new('archive_tarball', tmpdir)
  File.open(tmpfile, 'wb') do |f|
    data = HTTParty.get(tarball_url).body
    f.write data
  end

  tmpfile
end

def random_archive
  repo = random_repo
  {repo: repo.full_name, tarball: download_archive(repo)}
end

def binary?(filename)
  fm = FileMagic.new(FileMagic::MAGIC_MIME)
  fm.file(filename) !~ /^text\//
ensure
  fm.close
end

def extract_random_file(tarball)
  output = `tar tzf #{tarball.path} | grep -e '[^/]$' 2>/dev/null`
  raise BadExampleError.new("Bad tarball.") unless $?.exitstatus.zero?
  files_in_tarball = output.lines
  raise BadExampleError.new("No files in tarball.") if files_in_tarball.empty?

  attempt = 1
  while attempt <= 5
    random_file = files_in_tarball.sample.chomp
    `tar xvf #{tarball.path} -C #{tmpdir} #{random_file} 2>/dev/null`
    raise BadExampleError.new("Bad tarball.") unless $?.exitstatus.zero?
    file_path = File.join tmpdir, random_file
    if binary?(file_path)
      STDERR.puts "Attempt ##{attempt} failed: File is binary."
      attempt += 1
    elsif file_path =~ /README|gitignore|gitattributes|npmignore|min\.js/
      STDERR.puts "Attempt ##{attempt} failed: File too boring."
      attempt += 1
    else
      return file_path
    end
  end

  raise BadExampleError.new("Couldn't find a usable file in tarball.")
end

def random_file_in_random_repo
  attempt = 1
  while attempt <= 100
    begin
      repo, tarball = random_archive.values_at :repo, :tarball
      return {repo: repo, filename: extract_random_file(tarball)}
    rescue BadExampleError => e
      STDERR.puts "Attempt ##{attempt} failed: #{e}"
      attempt += 1
    end
  end
end

def format_code(filename)
  File.open filename do |file|
    file.sync = true
    source = file.read
    raise BadExampleError.new("Source file is empty.") if source =~ /^\s*$/
    lexer = Rouge::Lexer.guess(source: source, filename: filename)
    formatter = Rouge::Formatters::HTML.new
    html = formatter.format(lexer.lex(source))
    random_theme = Rouge::Theme.registry.values.sample
    css = random_theme.render(scope: 'body')
    {html: html, css: css}
  end
rescue Rouge::Guesser::Ambiguous, ArgumentError
  msg = "Unable to detect filetype for syntax highlighting."
  raise BadExampleError.new(msg)
end

# Collected manually on 12/16/17.
$monospace_google_fonts = [
 "Anonymous Pro",
 "Cousine",
 "Cutive Mono",
 "Fira Mono",
 "Inconsolata",
 "Nova Mono",
 "Overpass Mono",
 "Oxygen Mono",
 "PT Mono",
 "Roboto Mono",
 "Share Tech Mono",
 "Source Code Pro",
 "Space Mono",
 "Ubuntu Mono",
 "VT323"
]

def code_view(filename)
  html, css = format_code(filename).values_at(:html, :css)
  font = $monospace_google_fonts.sample
  font_link = "https://fonts.googleapis.com/css?family=#{font.gsub ' ', '+'}"

  <<~EOF
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
  EOF
end

def random_code_view
  attempt = 1

  while attempt <= 100
    begin
      repo, filename = random_file_in_random_repo.values_at :repo, :filename
      return {repo: repo, filename: filename, html: code_view(filename)}
    rescue BadExampleError => e
      STDERR.puts "Attempt ##{attempt} failed: #{e}"
      attempt += 1
    end
  end
end

def random_screenshot(in_html, out_png)
  browser = Watir::Browser.new :chrome,
    headless: true,
    switches: ['--hide-scrollbars']
  browser.goto "file://#{in_html}"
  unless browser.title == 'code view'
    raise "File not found: #{in_html}"
  end
  # Determine the screen resolution of the machine running this script.
  width, height = `xrandr`.scan(/current (\d+) x (\d+)/).flatten.map(&:to_i)
  # Maximize the window to fullscreen.
  browser.window.resize_to width, height
  # Wait until the `pre` element is rendered before taking a screenshot.
  #
  # NB: I tried: browser.pre.wait_until_present
  #         and: browser.pre.wait_until {|pre| !pre.text.empty?}
  #
  #     but neither of these seemed to do the trick. The screenshot was still
  #     being taken before the code was being rendered in the `pre` element. In
  #     cases where there was a lot of code, this resulted in an empty
  #     screenshot.
  #
  #     Hard-coding a sleep of 5 seconds is not an ideal solution, but it gets
  #     the job done.
  sleep 5
  # Scroll down to a random position (Y coordinate) on the page.
  x = 0
  y = Random.rand 0..[browser.body.height / 2 - height, 0].max
  browser.scroll.to [x, y]
  browser.screenshot.save(out_png)
ensure
  browser.quit
end

if __FILE__ == $0
  with_tmpdir do
    File.open(Tempfile.new(['code_view', '.html'], tmpdir), 'wb') do |file|
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
end

