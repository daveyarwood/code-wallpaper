# code-wallpaper

A script that generates desktop wallpaper that displays excerpts of actual code
obtained from random files in random public GitHub repositories.

## Usage

After [setting up your environment](#setup) so that you can run the script,
simply run `bundle exec generate-wallpaper.rb`. The script will do its thing and
create a PNG file in the current directory.

```bash
$ bundle exec generate-wallpaper.rb 2>/dev/null
20171217220938-giorgil2-mixico-version.rb.png
```

The resulting filename includes, in order:

* The current timestamp (`YYYYMMDDHHmmss`)
* The GitHub user/organization
* The repository name
* The name of the source file

## Examples

<center>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217063126-johnnywang1991-RexInline-Rex::Inline::Base.3pm.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217063126-johnnywang1991-RexInline-Rex::Inline::Base.3pm.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217202947-infelane-starlight-1237648673995162093-i.csv.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217202947-infelane-starlight-1237648673995162093-i.csv.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212626-benjaminr177-git-push33n-kitteh5.maow.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212626-benjaminr177-git-push33n-kitteh5.maow.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212641-Evyy-entwinedDev-twitterfeed.js.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212641-Evyy-entwinedDev-twitterfeed.js.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212858-doge-dog-dirtycow.github.io-pokemon.c.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212858-doge-dog-dirtycow.github.io-pokemon.c.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212934-ryanmrichard-Pulsar-Core-d-methionine.py.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217212934-ryanmrichard-Pulsar-Core-d-methionine.py.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217213449-suprabhatgurrala-gcd-coursera-project-UCI_HAR_Tidy.csv.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217213449-suprabhatgurrala-gcd-coursera-project-UCI_HAR_Tidy.csv.png?raw=true" />
</a>

<a href="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217213845-ReekenX-jquery-cutetime-lt-translation-jquery.cutetime.settings.lt.js.png?raw=true">
  <img src="https://github.com/daveyarwood/code-wallpaper/blob/master/examples/20171217213845-ReekenX-jquery-cutetime-lt-translation-jquery.cutetime.settings.lt.js.png?raw=true" />
</a>

</center>

## Why?

For a few reasons:

* The ideas of creating [algorithmic
  art](https://en.wikipedia.org/wiki/Algorithmic_art) and art from [found
  objects](https://en.wikipedia.org/wiki/Found_object) are interesting to me.

  It occurred to me that there are tens of millions of code repositories in
  GitHub, many of which happen to contain text excerpts that are interesting
  from an artistic perspective.

* I'm indecisive about my wallpaper and lock screen backgrounds. I thought it
  might be cool if I had a way to generate interesting backgrounds and
  cycle them regularly via a cron job.

* Writing the script was a fun exercise in the GitHub API, tarball processing,
  syntax highlighting, and headless browsers.

## How?

* We make a GitHub API request to get the archive download link for a random
  public repository.

* We download the archive (a tarball) and extract a file at random, excluding
  binary files and files that will probably not be all that interesting, based
  on the filename (README, gitignore, minified JavaScript files).

* We spit the contents of the file out into a code block in an HTML file, and
  use [Rouge](https://github.com/jneen/rouge) to add syntax highlighting.

* Using a headless browser ([Watir](https://github.com/watir/watir)), we view
  the HTML file, scroll to a random position, and take a screenshot.

## Setup

### Environment

This script requires a Unix environment with `xrandr` installed for the purposes
of determining the width and height of the screen. In the absence of an OS where
`xrandr` is readily available (perhaps yours doesn't use X Windows), as a
workaround, you can create an `xrandr` script somewhere on your `$PATH` that
prints a line like the following:

```
current 1920 x 1080
```

If you know your screen resolution, you can simply hard-code it into the script.

### GitHub authorization

This script uses the GitHub API to fetch code from GitHub. This requires a
personal access token, [which can be created easily](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/) in the GitHub UI.

After creating a personal access token, export it as an environment variable
called `GITHUB_TOKEN`:

```bash
$ export GITHUB_TOKEN=paste-your-token-here
```

### Ruby

This script requires Ruby 2.3+ and [Bundler](http://bundler.io/).

### Ruby libraries

Run `bundle install` to install the libraries the script depends on into
`./vendor/bundle`.

## License

Copyright © 2017-2018 Dave Yarwood

Distributed under the Eclipse Public License version 2.0.
