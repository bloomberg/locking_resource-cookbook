require 'spec_helper'

describe Locking_Resource::Helper do
  describe '#hwx_pkg_str' do
    let(:dummy_class) do
      Class.new do
        include Bcpc_Hadoop::Helper
      end
    end

    raw_version = '1.2.3.4-1234'
    hyphenated_version = '1-2-3-4-1234'

    context '#hwx_pkg_str' do

      it 'inserts version at end of short package name' do
        expect(dummy_class.new.hwx_pkg_str('foobar', raw_version)).to eq("foobar-#{hyphenated_version}")
      end

      it 'inserts version at frist hyphen of hyphenated package' do
        expect(dummy_class.new.hwx_pkg_str('foo-bar', raw_version)).to eq("foo-#{hyphenated_version}-bar")
      end
    end
  end
end
