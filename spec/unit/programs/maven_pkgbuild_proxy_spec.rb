require 'spec_helper'
require 'open3'

# Regression guard for PKGBUILDs that build with Maven.
#
# Maven runs on the JVM, which ignores the http_proxy/https_proxy environment
# variables every other build tool honors. Behind a proxy, a bare "mvn" call
# hangs downloading plugins from Maven Central until the build times out, so
# every PKGBUILD invoking mvn must translate those variables into JVM proxy
# properties (see set_maven_proxy in programs/linkbench/pkg/PKGBUILD).
describe 'PKGBUILDs using Maven' do
  pkgbuilds = Dir[File.join(LKP_SRC, 'programs', '*', 'pkg', 'PKGBUILD')].select do |path|
    File.read(path).match?(/^\s*mvn\s/)
  end

  it 'finds at least one Maven-based PKGBUILD' do
    expect(pkgbuilds).not_to be_empty
  end

  pkgbuilds.each do |pkgbuild|
    it "#{pkgbuild.delete_prefix("#{LKP_SRC}/")} configures the JVM proxy before calling mvn" do
      content = File.read(pkgbuild)
      expect(content).to match(/\.proxyHost/)
    end
  end

  describe 'linkbench set_maven_proxy' do
    let(:pkgbuild) { File.join(LKP_SRC, 'programs', 'linkbench', 'pkg', 'PKGBUILD') }
    let(:function_source) { File.read(pkgbuild)[/^set_maven_proxy\(\)\n\{.*?^\}/m] }

    def maven_opts(proxy_env)
      script = "#{function_source}\nMAVEN_OPTS=''\nset_maven_proxy\necho \"$MAVEN_OPTS\""
      out, = Open3.capture2(proxy_env, 'bash', '-c', script, unsetenv_others: true)
      out.strip
    end

    it 'extracts the function from the PKGBUILD' do
      expect(function_source).not_to be_nil
    end

    it 'maps a proxy URL with a port to host and port properties' do
      opts = maven_opts('http_proxy' => 'http://proxy.example:913', 'https_proxy' => 'http://proxy.example:913')
      expect(opts).to eq('-Dhttp.proxyHost=proxy.example -Dhttp.proxyPort=913 ' \
                         '-Dhttps.proxyHost=proxy.example -Dhttps.proxyPort=913')
    end

    it 'drops credentials and a trailing path from the proxy URL' do
      opts = maven_opts('https_proxy' => 'http://user:pw@proxy.example:8080/')
      expect(opts).to eq('-Dhttps.proxyHost=proxy.example -Dhttps.proxyPort=8080')
    end

    it 'omits the port property when the proxy URL has no port' do
      expect(maven_opts('http_proxy' => 'proxy.example')).to eq('-Dhttp.proxyHost=proxy.example')
    end

    it 'leaves MAVEN_OPTS empty when no proxy is configured' do
      expect(maven_opts({})).to eq('')
    end
  end
end
