require 'mechanize'
require 'yaml'

module Homebrew
  class Geoserver

    attr_reader :remote_version, :local_version

    GEOSERVER_URL     = ENV.fetch('GEOSERVER_URL', 'http://geoserver.org/')
    VERSION_FILE      = ENV.fetch('VERSION_FILE', 'version.yml')
    DOWNLOAD_LOCATION = ENV.fetch('DOWNLOAD_LOCATION', '/tmp')
    HOMEBREW_PATH     = ENV.fetch('HOMEBREW_PATH', "#{Dir.home}/projects/homebrew")

    def initialize
      @agent = Mechanize.new
      @remote_version = get_remote_version.to_s
      @local_version = YAML::load_file(VERSION_FILE)['version']
    end

    def get_remote_version
      @agent.get(GEOSERVER_URL) do |page|
        return page.link_with(:href => '/release/stable')
      end
    end

    def update_homebrew
      Dir.chdir(HOMEBREW_PATH) do
        `git checkout master`
        `git pull upstream master`
        `git checkout -b #{remote_version}`
      end
    end

    def push_update
      Dir.chdir(HOMEBREW_PATH) do
        `git push origin #{remote_version}`
      end
    end

    def version_compare
      remote = Gem::Version.new(@remote_version)
      local = Gem::Version.new(@local_version)

      if remote > local
        puts "There is a new version. Downloading to /tmp"
        download_geoserver

        puts "Updating the recipe"
        update_recipe

        puts "Updating local version cache"
        update_yaml

        puts "Pushing update to GH"
        push_update
      else
        puts "Nothing to do..."
      end
    end

    def download_geoserver
      url = "https://downloads.sourceforge.net/project/geoserver/GeoServer/#{remote_version}/geoserver-#{remote_version}-bin.zip"
      `wget -P /tmp #{url}`
    end

    def checksum
      sha = `shasum -a 256 /tmp/geoserver-#{remote_version}-bin.zip`
      sha.split(' ').first
    end

    def update_yaml
      File.open(VERSION_FILE, 'w') {|f| f.write( "version: #{@remote_version}" ).to_yaml }
    end

    def update_recipe
      File.open("#{HOMEBREW_PATH}/Library/Formula/geoserver.rb", 'w') {|f| f.write recipe_template }
    end

    def recipe_template
      recipe = <<-BLOCK
require 'formula'

class Geoserver < Formula
  desc "Java server to share and edit geospatial data"
  homepage 'http://geoserver.org/'
  url 'https://downloads.sourceforge.net/project/geoserver/GeoServer/#{@remote_version}/geoserver-#{@remote_version}-bin.zip'
  sha256 '#{self.checksum}'

  def install
    libexec.install Dir['*']
    (bin/'geoserver').write <<-EOS.undent
      #!/bin/sh
      if [ -z "$1" ]; then
        echo "Usage: $ geoserver path/to/data/dir"
      else
        cd "\#{libexec}" && java -DGEOSERVER_DATA_DIR=$1 -jar start.jar
      fi
    EOS
  end

  def caveats; <<\-EOS.undent
    To start geoserver:
      geoserver path/to/data/dir
    See the Geoserver homepage for more setup information:
      brew home geoserver
    EOS
  end
end
      BLOCK

      recipe
    end

  end
end

updater = Homebrew::Geoserver.new
updater.version_compare
