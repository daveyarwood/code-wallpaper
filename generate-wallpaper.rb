#!/usr/bin/env ruby

gem 'httparty', '0.15.6'
gem 'octokit', '~> 4.0'
gem 'rouge', '3.0.0'
gem 'ruby-filemagic', '0.7.2'

require 'filemagic'
require 'httparty'
require 'octokit'
require 'rouge'
require 'tempfile'
require 'tmpdir'

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
  download_archive random_repo
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
      STDERR.puts "Attempt ##{attempt} failed: file is binary"
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
      return extract_random_file random_archive
    rescue BadExampleError => e
      STDERR.puts "Attempt ##{attempt} failed: #{e}"
      attempt += 1
    end
  end
end

def format_code(filename)
  File.open filename do |file|
    source = file.read
    lexer = Rouge::Lexer.guess(source: source, filename: filename)
    formatter = Rouge::Formatters::HTML.new
    html = formatter.format(lexer.lex(source))
    random_theme = Rouge::Theme.registry.values.sample
    css = random_theme.render(scope: 'body')
    {html: html, css: css}
  end
rescue Rouge::Guesser::Ambiguous
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
  pre { font-family: '#{font}', monospace; font-size: 1.75em; }
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
      return code_view(random_file_in_random_repo)
    rescue BadExampleError => e
      STDERR.puts "Attempt #{attempt} failed: #{e}"
      attempts += 1
    end
  end
end

# testing
def go
  with_tmpdir do
    File.open('/tmp/foop.html', 'wb') do |file|
      file.write random_code_view
    end
  end
end

