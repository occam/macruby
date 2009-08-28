require File.dirname(__FILE__) + '/../../spec_helper'
require File.expand_path(File.dirname(__FILE__) + '/../fixtures/classes')

describe "Regexps with encoding modifiers" do

  # Note: The encoding implied by a given modifier is specified in
  # core/regexp/encoding_spec.rb for 1.9

  ruby_version_is ""..."1.9" do
    not_compliant_on :macruby do
      it 'supports /e (EUC encoding)' do
        match = /./e.match("\303\251")
        match.to_a.should == ["\303\251"]
      end
      
      it 'supports /n (Normal encoding)' do
        /./n.match("\303\251").to_a.should == ["\303"]
      end
      
      it 'supports /s (SJIS encoding)' do
        /./s.match("\303\251").to_a.should == ["\303"]
      end
      
      it 'supports /u (UTF8 encoding)' do
        /./u.match("\303\251").to_a.should == ["\303\251"]
      end
      
      it 'selects last of multiple encoding specifiers' do
        /foo/ensuensuens.should == /foo/s
      end
    end
  end

  ruby_version_is "1.9" do
    it 'supports /e (EUC encoding)' do
      match = /./e.match("\303\251".force_encoding(Encoding::EUC_JP))
      match.to_a.should == ["\303\251".force_encoding(Encoding::EUC_JP)]
    end
    
    it 'supports /n (Normal encoding)' do
      /./n.match("\303\251").to_a.should == ["\303"]
    end
    
    it 'supports /s (Windows_31J encoding)' do
      match = /./s.match("\303\251".force_encoding(Encoding::Windows_31J))
      match.to_a.should == ["\303".force_encoding(Encoding::Windows_31J)]
    end
    
    it 'supports /u (UTF8 encoding)' do
      /./u.match("\303\251".force_encoding('utf-8')).to_a.should == ["\u{e9}"]
    end
    
    it 'selects last of multiple encoding specifiers' do
      /foo/ensuensuens.should == /foo/s
    end
  end
end
