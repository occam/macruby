require 'test/unit'

class TestRegexp < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_ruby_dev_24643
    assert_nothing_raised("[ruby-dev:24643]") {
      /(?:(?:[a]*[a])?b)*a*$/ =~ "aabaaca"
    }
  end

  def test_ruby_talk_116455
    assert_match(/^(\w{2,}).* ([A-Za-z\xa2\xc0-\xff]{2,}?)$/n, "Hallo Welt")
  end

  def test_ruby_dev_24887
    assert_equal("a".gsub(/a\Z/, ""), "")
  end

  def test_yoshidam_net_20041111_1
    s = "[\xC2\xA0-\xC3\xBE]"
    assert_match(Regexp.new(s, nil, "u"), "\xC3\xBE")
  end

  def test_yoshidam_net_20041111_2
    assert_raise(RegexpError) do
      s = "[\xFF-\xFF]".force_encoding("utf-8")
      Regexp.new(s, nil, "u")
    end
  end

  def test_ruby_dev_31309
    assert_equal('Ruby', 'Ruby'.sub(/[^a-z]/i, '-'))
  end

  def test_assert_normal_exit
    # moved from knownbug.  It caused core.
    Regexp.union("a", "a")
  end

  def test_to_s
    assert_equal '(?-mix:\x00)', Regexp.new("\0").to_s
  end

  def test_union
    assert_equal :ok, begin
      Regexp.union(
        "a",
        Regexp.new("\xc2\xa1".force_encoding("euc-jp")),
        Regexp.new("\xc2\xa1".force_encoding("utf-8")))
      :ng
    rescue ArgumentError
      :ok
    end
  end

  def test_named_capture
    m = /&(?<foo>.*?);/.match("aaa &amp; yyy")
    assert_equal("amp", m["foo"])
    assert_equal("amp", m[:foo])
    assert_equal(5, m.begin(:foo))
    assert_equal(8, m.end(:foo))
    assert_equal([5,8], m.offset(:foo))

    assert_equal("aaa [amp] yyy",
      "aaa &amp; yyy".sub(/&(?<foo>.*?);/, '[\k<foo>]'))

    assert_equal('#<MatchData "&amp; y" foo:"amp">',
      /&(?<foo>.*?); (y)/.match("aaa &amp; yyy").inspect)
    assert_equal('#<MatchData "&amp; y" 1:"amp" 2:"y">',
      /&(.*?); (y)/.match("aaa &amp; yyy").inspect)
    assert_equal('#<MatchData "&amp; y" foo:"amp" bar:"y">',
      /&(?<foo>.*?); (?<bar>y)/.match("aaa &amp; yyy").inspect)
    assert_equal('#<MatchData "&amp; y" foo:"amp" foo:"y">',
      /&(?<foo>.*?); (?<foo>y)/.match("aaa &amp; yyy").inspect)

    /(?<id>[A-Za-z_]+)/ =~ "!abc"
    assert_equal("abc", Regexp.last_match(:id))

    /a/ =~ "b" # doesn't match.
    assert_equal(nil, Regexp.last_match)
    assert_equal(nil, Regexp.last_match(1))
    assert_equal(nil, Regexp.last_match(:foo))

    assert_equal(["foo", "bar"], /(?<foo>.)(?<bar>.)/.names)
    assert_equal(["foo"], /(?<foo>.)(?<foo>.)/.names)
    assert_equal([], /(.)(.)/.names)

    assert_equal(["foo", "bar"], /(?<foo>.)(?<bar>.)/.match("ab").names)
    assert_equal(["foo"], /(?<foo>.)(?<foo>.)/.match("ab").names)
    assert_equal([], /(.)(.)/.match("ab").names)

    assert_equal({"foo"=>[1], "bar"=>[2]},
                 /(?<foo>.)(?<bar>.)/.named_captures)
    assert_equal({"foo"=>[1, 2]},
                 /(?<foo>.)(?<foo>.)/.named_captures)
    assert_equal({}, /(.)(.)/.named_captures)

    assert_equal("a[b]c", "abc".sub(/(?<x>[bc])/, "[\\k<x>]"))
  end

  def test_assign_named_capture
    assert_equal("a", eval('/(?<foo>.)/ =~ "a"; foo'))
    assert_equal("a", eval('foo = 1; /(?<foo>.)/ =~ "a"; foo'))
    assert_equal("a", eval('1.times {|foo| /(?<foo>.)/ =~ "a"; break foo }'))
    assert_nothing_raised { eval('/(?<Foo>.)/ =~ "a"') }
    assert_nil(eval('/(?<Foo>.)/ =~ "a"; defined? Foo'))
  end

  def test_assign_named_capture_to_reserved_word
    /(?<nil>.)/ =~ "a"
    assert(!local_variables.include?(:nil), "[ruby-dev:32675]")
  end

  def test_match_regexp
    r = /./
    m = r.match("a")
    assert_equal(r, m.regexp)
  end

  def test_source
    assert_equal('', //.source)
  end

  def test_inspect
    assert_equal('//', //.inspect)
    assert_equal('//i', //i.inspect)
    assert_equal('/\//i', /\//i.inspect)
    assert_equal('/\//i', /#{'/'}/i.inspect)
    assert_equal('/\/x/i', /\/x/i.inspect)
    assert_equal('/\x00/i', /#{"\0"}/i.inspect)
    assert_equal("/\n/i", /#{"\n"}/i.inspect)
    s = [0xff].pack("C")
    assert_equal('/\/'+s+'/i', /\/#{s}/i.inspect)
  end

  def test_char_to_option
    assert_equal("BAR", "FOOBARBAZ"[/b../i])
    assert_equal("bar", "foobarbaz"[/  b  .  .  /x])
    assert_equal("bar\n", "foo\nbar\nbaz"[/b.../m])
    assert_raise(SyntaxError) { eval('//z') }
  end

  def test_char_to_option_kcode
    assert_equal("bar", "foobarbaz"[/b../s])
    assert_equal("bar", "foobarbaz"[/b../e])
    assert_equal("bar", "foobarbaz"[/b../u])
  end

  def test_to_s2
    assert_equal('(?-mix:foo)', /(?:foo)/.to_s)
    assert_equal('(?m-ix:foo)', /(?:foo)/m.to_s)
    assert_equal('(?mi-x:foo)', /(?:foo)/mi.to_s)
    assert_equal('(?mix:foo)', /(?:foo)/mix.to_s)
    assert_equal('(?m-ix:foo)', /(?m-ix:foo)/.to_s)
    assert_equal('(?mi-x:foo)', /(?mi-x:foo)/.to_s)
    assert_equal('(?mix:foo)', /(?mix:foo)/.to_s)
    assert_equal('(?mix:)', /(?mix)/.to_s)
    assert_equal('(?-mix:(?mix:foo) )', /(?mix:foo) /.to_s)
  end

  def test_casefold_p
    assert_equal(false, /a/.casefold?)
    assert_equal(true, /a/i.casefold?)
    assert_equal(false, /(?i:a)/.casefold?)
  end

  def test_options
    assert_equal(Regexp::IGNORECASE, /a/i.options)
    assert_equal(Regexp::EXTENDED, /a/x.options)
    assert_equal(Regexp::MULTILINE, /a/m.options)
  end

  def test_match_init_copy
    m = /foo/.match("foo")
    assert_equal(/foo/, m.dup.regexp)
    assert_raise(TypeError) do
      m.instance_eval { initialize_copy(nil) }
    end
    assert_equal([0, 3], m.offset(0))
    assert_equal(/foo/, m.dup.regexp)
  end

  def test_match_regexp
    re = /foo/
    assert_equal(re, re.match("foo").regexp)
  end

  def test_match_size
    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
    assert_equal(5, m.size)
  end

  def test_match_offset_begin_end
    m = /(?<x>b..)/.match("foobarbaz")
    assert_equal([3, 6], m.offset("x"))
    assert_equal(3, m.begin("x"))
    assert_equal(6, m.end("x"))
    assert_raise(IndexError) { m.offset("y") }
    assert_raise(IndexError) { m.offset(2) }
    assert_raise(IndexError) { m.begin(2) }
    assert_raise(IndexError) { m.end(2) }

    m = /(?<x>q..)?/.match("foobarbaz")
    assert_equal([nil, nil], m.offset("x"))
    assert_equal(nil, m.begin("x"))
    assert_equal(nil, m.end("x"))

    m = /\A\u3042(.)(.)?(.)\z/.match("\u3042\u3043\u3044")
    assert_equal([1, 2], m.offset(1))
    assert_equal([nil, nil], m.offset(2))
    assert_equal([2, 3], m.offset(3))
  end

  def test_match_to_s
    m = /(?<x>b..)/.match("foobarbaz")
    assert_equal("bar", m.to_s)
  end

  def test_match_pre_post
    m = /(?<x>b..)/.match("foobarbaz")
    assert_equal("foo", m.pre_match)
    assert_equal("baz", m.post_match)
  end

  def test_match_array
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal(["foobarbaz", "foo", "bar", "baz", nil], m.to_a)
  end

  def test_match_captures
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal(["foo", "bar", "baz", nil], m.captures)
  end

  def test_match_aref
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal("foo", m[1])
    assert_equal(["foo", "bar", "baz"], m[1..3])
    assert_nil(m[5])
    assert_raise(IndexError) { m[:foo] }
  end

  def test_match_values_at
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal(["foo", "bar", "baz"], m.values_at(1, 2, 3))
  end

  def test_match_string
    m = /(?<x>b..)/.match("foobarbaz")
    assert_equal("foobarbaz", m.string)
  end

  def test_match_inspect
    m = /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal('#<MatchData "foobarbaz" 1:"foo" 2:"bar" 3:"baz" 4:nil>', m.inspect)
  end

  def test_initialize
    assert_raise(ArgumentError) { Regexp.new }
    assert_equal(/foo/, Regexp.new(/foo/, Regexp::IGNORECASE))
    re = /foo/
    assert_raise(SecurityError) do
      Thread.new { $SAFE = 4; re.instance_eval { initialize(re) } }.join
    end
    re.taint
    assert_raise(SecurityError) do
      Thread.new { $SAFE = 4; re.instance_eval { initialize(re) } }.join
    end

    assert_equal(Encoding::ASCII_8BIT, Regexp.new("b..", nil, "n").encoding)
    assert_equal("bar", "foobarbaz"[Regexp.new("b..", nil, "n")])

    assert_raise(RegexpError) { Regexp.new(")(") }
  end

  def test_unescape
    assert_raise(ArgumentError) { s = '\\'; /#{ s }/ }
    assert_equal(/\177/, (s = '\177'; /#{ s }/))
    assert_raise(ArgumentError) { s = '\u'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\u{ ffffffff }'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\u{ ffffff }'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\u{ ffff X }'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\u{ }'; /#{ s }/ }
    assert_equal("b", "abc"[(s = '\u{0062}'; /#{ s }/)])
    assert_equal("b", "abc"[(s = '\u0062'; /#{ s }/)])
    assert_raise(ArgumentError) { s = '\u0'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\u000X'; /#{ s }/ }
    assert_raise(ArgumentError) { s = "\xff" + '\u3042'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\u3042' + [0xff].pack("C"); /#{ s }/ }
    assert_raise(SyntaxError) { s = ''; eval(%q(/\u#{ s }/)) }

    assert_equal(/a/, eval(%q(s="\u0061";/#{s}/n)))
    assert_raise(RegexpError) { s = "\u3042"; eval(%q(/#{s}/n)) }
    assert_raise(RegexpError) { s = "\u0061"; eval(%q(/\u3042#{s}/n)) }
    assert_raise(ArgumentError) { s1=[0xff].pack("C"); s2="\u3042"; eval(%q(/#{s1}#{s2}/)) }

    assert_raise(ArgumentError) { s = '\x'; /#{ s }/ }

    assert_equal("\xe1", [0x00, 0xe1, 0xff].pack("C*")[/\M-a/])
    assert_equal("\xdc", [0x00, 0xdc, 0xff].pack("C*")[/\M-\\/])
    assert_equal("\x8a", [0x00, 0x8a, 0xff].pack("C*")[/\M-\n/])
    assert_equal("\x89", [0x00, 0x89, 0xff].pack("C*")[/\M-\t/])
    assert_equal("\x8d", [0x00, 0x8d, 0xff].pack("C*")[/\M-\r/])
    assert_equal("\x8c", [0x00, 0x8c, 0xff].pack("C*")[/\M-\f/])
    assert_equal("\x8b", [0x00, 0x8b, 0xff].pack("C*")[/\M-\v/])
    assert_equal("\x87", [0x00, 0x87, 0xff].pack("C*")[/\M-\a/])
    assert_equal("\x9b", [0x00, 0x9b, 0xff].pack("C*")[/\M-\e/])
    assert_equal("\x01", [0x00, 0x01, 0xff].pack("C*")[/\C-a/])

    assert_raise(ArgumentError) { s = '\M'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\M-\M-a'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\M-\\'; /#{ s }/ }

    assert_raise(ArgumentError) { s = '\C'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\c'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\C-\C-a'; /#{ s }/ }

    assert_raise(ArgumentError) { s = '\M-\z'; /#{ s }/ }
    assert_raise(ArgumentError) { s = '\M-\777'; /#{ s }/ }

    assert_equal("\u3042\u3042", "\u3042\u3042"[(s = "\u3042" + %q(\xe3\x81\x82); /#{s}/)])
    assert_raise(ArgumentError) { s = "\u3042" + %q(\xe3); /#{s}/ }
    assert_raise(ArgumentError) { s = "\u3042" + %q(\xe3\xe3); /#{s}/ }
    assert_raise(ArgumentError) { s = '\u3042' + [0xff].pack("C"); /#{s}/ }

    assert_raise(SyntaxError) { eval("/\u3042/n") }

    s = ".........."
    5.times { s.sub!(".", "") }
    assert_equal(".....", s)
  end

  def test_equal
    assert_equal(true, /abc/ == /abc/)
    assert_equal(false, /abc/ == /abc/m)
    assert_equal(false, /abc/ == /abd/)
  end

  def test_match
    assert_nil(//.match(nil))
    assert_equal("abc", /.../.match(:abc)[0])
    assert_raise(TypeError) { /.../.match(Object.new)[0] }
    assert_equal("bc", /../.match('abc', 1)[0])
    assert_equal("bc", /../.match('abc', -2)[0])
    assert_nil(/../.match("abc", -4))
    assert_nil(/../.match("abc", 4))
    assert_equal('\x', /../n.match("\u3042" + '\x', 1)[0])

    r = nil
    /.../.match("abc") {|m| r = m[0] }
    assert_equal("abc", r)

    $_ = "abc"; assert_equal(1, ~/bc/)
    $_ = "abc"; assert_nil(~/d/)
    $_ = nil; assert_nil(~/./)
  end

  def test_eqq
    assert_equal(false, /../ === nil)
  end

  def test_quote
    assert_equal("\xff", Regexp.quote([0xff].pack("C")))
    assert_equal("\\ ", Regexp.quote("\ "))
    assert_equal("\\t", Regexp.quote("\t"))
    assert_equal("\\n", Regexp.quote("\n"))
    assert_equal("\\r", Regexp.quote("\r"))
    assert_equal("\\f", Regexp.quote("\f"))
    assert_equal("\\v", Regexp.quote("\v"))
    assert_equal("\u3042\\t", Regexp.quote("\u3042\t"))
    assert_equal("\\t\xff", Regexp.quote("\t" + [0xff].pack("C")))
  end

  def test_try_convert
    assert_equal(/re/, Regexp.try_convert(/re/))
    assert_nil(Regexp.try_convert("re"))

    o = Object.new
    assert_nil(Regexp.try_convert(o))
    def o.to_regexp() /foo/ end
    assert_equal(/foo/, Regexp.try_convert(o))
  end

  def test_union2
    assert_equal(/(?!)/, Regexp.union)
    assert_equal(/foo/, Regexp.union(/foo/))
    assert_equal(/foo/, Regexp.union([/foo/]))
    assert_equal(/\t/, Regexp.union("\t"))
    assert_equal(/(?-mix:\u3042)|(?-mix:\u3042)/, Regexp.union(/\u3042/, /\u3042/))
    assert_equal("\u3041", "\u3041"[Regexp.union(/\u3042/, "\u3041")])
  end

  def test_dup
    assert_equal(//, //.dup)
    assert_raise(TypeError) { //.instance_eval { initialize_copy(nil) } }
  end

  def test_regsub
    assert_equal("fooXXXbaz", "foobarbaz".sub!(/bar/, "XXX"))
    s = [0xff].pack("C")
    assert_equal(s, "X".sub!(/./, s))
    assert_equal('\\' + s, "X".sub!(/./, '\\' + s))
    assert_equal('\k', "foo".sub!(/.../, '\k'))
    assert_raise(RuntimeError) { "foo".sub!(/(?<x>o)/, '\k<x') }
    assert_equal('foo[bar]baz', "foobarbaz".sub!(/(b..)/, '[\0]'))
    assert_equal('foo[foo]baz', "foobarbaz".sub!(/(b..)/, '[\`]'))
    assert_equal('foo[baz]baz', "foobarbaz".sub!(/(b..)/, '[\\\']'))
    assert_equal('foo[r]baz', "foobarbaz".sub!(/(b)(.)(.)/, '[\+]'))
    assert_equal('foo[\\]baz', "foobarbaz".sub!(/(b..)/, '[\\\\]'))
    assert_equal('foo[\z]baz', "foobarbaz".sub!(/(b..)/, '[\z]'))
  end

  def test_KCODE
    assert_nil($KCODE)
    assert_nothing_raised { $KCODE = nil }
    assert_equal(false, $=)
    assert_nothing_raised { $= = nil }
  end

  def test_match_setter
    /foo/ =~ "foo"
    m = $~
    /bar/ =~ "bar"
    $~ = m
    assert_equal("foo", $&)
  end

  def test_last_match
    /(...)(...)(...)(...)?/.match("foobarbaz")
    assert_equal("foobarbaz", Regexp.last_match(0))
    assert_equal("foo", Regexp.last_match(1))
    assert_nil(Regexp.last_match(5))
    assert_nil(Regexp.last_match(-1))
  end

  def test_getter
    alias $__REGEXP_TEST_LASTMATCH__ $&
    alias $__REGEXP_TEST_PREMATCH__ $`
    alias $__REGEXP_TEST_POSTMATCH__ $'
    alias $__REGEXP_TEST_LASTPARENMATCH__ $+
    /(b)(.)(.)/.match("foobarbaz")
    assert_equal("bar", $__REGEXP_TEST_LASTMATCH__)
    assert_equal("foo", $__REGEXP_TEST_PREMATCH__)
    assert_equal("baz", $__REGEXP_TEST_POSTMATCH__)
    assert_equal("r", $__REGEXP_TEST_LASTPARENMATCH__)

    /(...)(...)(...)/.match("foobarbaz")
    assert_equal("baz", $+)
  end

  def test_rindex_regexp
    assert_equal(3, "foobarbaz\u3042".rindex(/b../n, 5))
  end

  def test_taint
    m = Thread.new do
      "foo"[/foo/]
      $SAFE = 4
      /foo/.match("foo")
    end.value
    assert(m.tainted?)
  end

  def check(re, ss, fs = [])
    re = Regexp.new(re) unless re.is_a?(Regexp)
    ss = [ss] unless ss.is_a?(Array)
    ss.each do |e, s|
      s ||= e
      m = re.match(s)
      assert_kind_of(MatchData, m)
      assert_equal(e, m[0])
    end
    fs = [fs] unless fs.is_a?(Array)
    fs.each {|s| assert_nil(re.match(s)) }
  end

  def failcheck(re)
    assert_raise(RegexpError) { /#{ re }/ }
  end

  def test_parse
    check(/\*\+\?\{\}\|\(\)\<\>\`\'/, "*+?{}|()<>`'")
    check(/\A\w\W\z/, %w(a. b!), %w(.. ab))
    check(/\A.\b.\b.\B.\B.\z/, %w(a.aaa .a...), %w(aaaaa .....))
    check(/\A\s\S\z/, [' a', "\n."], ['  ', "\n\n", 'a '])
    check(/\A\d\D\z/, '0a', %w(00 aa))
    check(/\A\h\H\z/, %w(0g ag BH), %w(a0 af GG))
    check(/\Afoo\Z\s\z/, "foo\n", ["foo", "foo\nbar"])
    assert_equal(%w(a b c), "abc def".scan(/\G\w/))
    check(/\A\u3042\z/, "\u3042", ["", "\u3043", "a"])
    check(/\A(..)\1\z/, %w(abab ....), %w(abba aba))
    failcheck('\1')
    check(/\A\80\z/, "80", ["\100", ""])
    check(/\A\77\z/, "?")
    check(/\A\78\z/, "\7" + '8', ["\100", ""])
    check(/\A\Qfoo\E\z/, "QfooE")
    check(/\Aa++\z/, "aaa")
    check('\Ax]\z', "x]")
    check(/x#foo/x, "x", "#foo")
    check(/\Ax#foo#{ "\n" }x\z/x, "xx", ["x", "x#foo\nx"])
    check(/\A\p{Alpha}\z/, ["a", "z"], [".", "", ".."])
    check(/\A\p{^Alpha}\z/, [".", "!"], ["!a", ""])
    check(/\A\n\z/, "\n")
    check(/\A\t\z/, "\t")
    check(/\A\r\z/, "\r")
    check(/\A\f\z/, "\f")
    check(/\A\a\z/, "\007")
    check(/\A\e\z/, "\033")
    check(/\A\v\z/, "\v")
  end

  def test_parse_kg
    check(/\A(.)(.)\k<1>(.)\z/, %w(abac abab ....), %w(abcd aaba xxx))
    check(/\A(.)(.)\k<-1>(.)\z/, %w(abbc abba ....), %w(abcd aaba xxx))
    check(/\A(?<n>.)(?<x>\g<n>){0}(?<y>\k<n+0>){0}\g<x>\g<y>\z/, "aba", "abb")
    check(/\A(?<n>.)(?<x>\g<n>){0}(?<y>\k<n+1>){0}\g<x>\g<y>\z/, "abb", "aba")
    check(/\A(?<x>..)\k<x>\z/, %w(abab ....), %w(abac abba xxx))
    check(/\A(.)(..)\g<-1>\z/, "abcde", %w(.... ......))
    failcheck('\k<x>')
    failcheck('\k<')
    failcheck('\k<>')
    failcheck('\k<.>')
    failcheck('\k<x.>')
    failcheck('\k<1.>')
    failcheck('\k<x')
    failcheck('\k<x+')
    failcheck('()\k<-2>')
    failcheck('()\g<-2>')
    check(/\A(?<x>.)(?<x>.)\k<x>\z/, %w(aba abb), %w(abc .. ....))
    check(/\k\g/, "kg")
  end

  def test_parse_curly_brace
    check(/\A{/, ["{", ["{", "{x"]])
    check(/\A{ /, ["{ ", ["{ ", "{ x"]])
    check(/\A{,}\z/, "{,}")
    check(/\A{}\z/, "{}")
    check(/\Aa{0}+\z/, "", %w(a aa aab))
    check(/\Aa{1}+\z/, %w(a aa), ["", "aab"])
    check(/\Aa{1,2}b{1,2}\z/, %w(ab aab abb aabb), ["", "aaabb", "abbb"])
    failcheck('.{100001}')
    failcheck('.{0,100001}')
    failcheck('.{1,0}')
    failcheck('{0}')
    failcheck('(?!x){0,1}')
  end

  def test_parse_comment
    check(/\A(?#foo\)bar)\z/, "", "a")
    failcheck('(?#')
  end

  def test_char_type
    check(/\u3042\d/, ["\u30421", "\u30422"])

    # CClassTable cache test
    assert(/\u3042\d/.match("\u30421"))
    assert(/\u3042\d/.match("\u30422"))
  end

  def test_char_class
    failcheck('[]')
    failcheck('[x')
    check('\A[]]\z', "]", "")
    check('\A[]\.]+\z', %w(] . ]..]), ["", "["])
    check(/\A[\u3042]\z/, "\u3042", "\u3042aa")
    check(/\A[\u3042\x61]+\z/, ["aa\u3042aa", "\u3042\u3042", "a"], ["", "b"])
    check(/\A[\u3042\x61\x62]+\z/, "abab\u3042abab\u3042")
    check(/\A[abc]+\z/, "abcba", ["", "ada"])
    check(/\A[\w][\W]\z/, %w(a. b!), %w(.. ab))
    check(/\A[\s][\S]\z/, [' a', "\n."], ['  ', "\n\n", 'a '])
    check(/\A[\d][\D]\z/, '0a', %w(00 aa))
    check(/\A[\h][\H]\z/, %w(0g ag BH), %w(a0 af GG))
    check(/\A[\p{Alpha}]\z/, ["a", "z"], [".", "", ".."])
    check(/\A[\p{^Alpha}]\z/, [".", "!"], ["!a", ""])
    check(/\A[\xff]\z/, "\xff", ["", "\xfe"])
    check(/\A[\80]+\z/, "8008", ["\\80", "\100", "\1000"])
    check(/\A[\77]+\z/, "???")
    check(/\A[\78]+\z/, "\788\7")
    check(/\A[\0]\z/, "\0")
    check(/\A[[:0]]\z/, [":", "0"], ["", ":0"])
    check(/\A[0-]\z/, ["0", "-"], "0-")
    check('\A[a-&&\w]\z', "a", "-")
    check('\A[--0]\z', ["-", "/", "0"], ["", "1"])
    check('\A[\'--0]\z', %w(* + \( \) 0 ,), ["", ".", "1"])
    check(/\A[a-b-]\z/, %w(a b -), ["", "c"])
    check('\A[a-b-&&\w]\z', %w(a b), ["", "-"])
    check('\A[a-b-&&\W]\z', "-", ["", "a", "b"])
    check('\A[a-c-e]\z', %w(a b c e), %w(- d)) # is it OK?
    check(/\A[a-f&&[^b-c]&&[^e]]\z/, %w(a d f), %w(b c e g 0))
    check(/\A[[^b-c]&&[^e]&&a-f]\z/, %w(a d f), %w(b c e g 0))
    check(/\A[\n\r\t]\z/, ["\n", "\r", "\t"])
  end

  def test_posix_bracket
    check(/\A[[:alpha:]0]\z/, %w(0 a), %w(1 .))
    check(/\A[[:^alpha:]0]\z/, %w(0 1 .), "a")
    check(/\A[[:alpha\:]]\z/, %w(a l p h a :), %w(b 0 1 .))
    check(/\A[[:alpha:foo]0]\z/, %w(0 a), %w(1 .))
    check(/\A[[:xdigit:]&&[:alpha:]]\z/, "a", %w(g 0))
    check('\A[[:abcdefghijklmnopqrstu:]]+\z', "[]")
    failcheck('[[:alpha')
    failcheck('[[:alpha:')
    failcheck('[[:alp:]]')
  end
end
