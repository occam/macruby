/**********************************************************************

  encoding.c -

  $Author: nobu $
  created at: Thu May 24 17:23:27 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "regenc.h"
#include <ctype.h>
#ifdef HAVE_LANGINFO_H
#include <langinfo.h>
#endif

static ID id_encoding, id_base_encoding;
static VALUE rb_cEncoding;

#if WITH_OBJC

static CFMutableDictionaryRef __encodings = NULL;

static VALUE
enc_new(const CFStringEncoding *enc)
{
    return Data_Wrap_Struct(rb_cEncoding, NULL, NULL, (void *)enc);
}

static void
enc_init_db(void)
{
    const CFStringEncoding *e;

    __encodings = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    
    e = CFStringGetListOfAvailableEncodings();
    while (e != NULL && *e != kCFStringEncodingInvalidId) {
	VALUE iana;
	VALUE encoding;

	encoding = enc_new(e);

	iana = (VALUE)CFStringConvertEncodingToIANACharSetName(*e);
	if (iana != 0) {
	    const char *name;
	    char *p;

	    name = RSTRING_CPTR(iana);
	    p = strchr(name, '-');
	    if ((p = strchr(name, '-')) != NULL
		|| islower(*name)) {
		char *tmp = alloca(strlen(name));
		strcpy(tmp, name);
		if (p != NULL) {
		    p = tmp + (p - name);
		    do {
			*p = '_';
			p++;
			p = strchr(p, '-');	
		    }
		    while (p != NULL);
		}
		if (islower(*tmp))
		    *tmp = toupper(*tmp);
		name = tmp;
	    }
	    rb_define_const(rb_cEncoding, name, encoding);
	}
	CFDictionarySetValue(__encodings, (const void *)(*e), 
	    (const void *)encoding);
	e++;
    }

    assert(CFDictionaryGetCount((CFDictionaryRef)__encodings) > 0);
}

static VALUE
enc_make(const CFStringEncoding *enc)
{
    VALUE v;
    v = (VALUE)CFDictionaryGetValue( (CFDictionaryRef)__encodings, 
	(const void *)(*enc));
    assert(v != 0);
    return v;
}

VALUE
rb_enc_from_encoding(rb_encoding *enc)
{
    return enc_make(enc);
}

static inline CFStringEncoding
rb_enc_to_enc(VALUE v)
{
    return *(CFStringEncoding *)DATA_PTR(v);
}

static inline CFStringEncoding *
rb_enc_to_enc_ptr(VALUE v)
{
    return (CFStringEncoding *)DATA_PTR(v);
}

rb_encoding *
rb_to_encoding(VALUE v)
{
    return rb_enc_to_enc_ptr(v);
}

#else

struct rb_encoding_entry {
    const char *name;
    rb_encoding *enc;
};

static struct {
    struct rb_encoding_entry *list;
    int count;
    int size;
    st_table *names;
} enc_table;

void rb_enc_init(void);

#ifndef NO_ENCDB_H
#undef ENC_REPLICATE
#undef ENC_ALIAS
#undef ENC_DUMMY
static int encdb_replicate(const char *alias, const char *orig);
static int encdb_alias(const char *alias, const char *orig);
static int encdb_dummy(const char *name);
static void encdb_declare(const char *name);
#define ENC_REPLICATE(name, orig) encdb_replicate(name, orig)
#define ENC_ALIAS(name, orig) encdb_alias(name, orig)
#define ENC_DUMMY(name) encdb_dummy(name)
#define ENC_DEFINE(name) encdb_declare(name)
#endif

static void
enc_init_db(void)
{
#ifdef NO_ENCDB_H
#define ENCODING_COUNT ENCINDEX_BUILTIN_MAX
#else
#include "encdb.h"
#endif
}

#define enc_autoload_p(enc) (!rb_enc_mbmaxlen(enc))

#define ENC_UNINITIALIZED (&rb_cEncoding)
#define enc_initialized_p(enc) ((enc)->auxiliary_data != &rb_cEncoding)
#define ENC_FROM_ENCODING(enc) ((VALUE)(enc)->auxiliary_data)

#define ENC_DUMMY_FLAG FL_USER2
#define ENC_DUMMY_P(enc) (RBASIC(enc)->flags & ENC_DUMMY_FLAG)
#define ENC_SET_DUMMY(enc) (RBASIC(enc)->flags |= ENC_DUMMY_FLAG)

static int load_encoding(const char *name);
static VALUE enc_base_encoding(VALUE self);

static void
enc_mark(void *ptr)
{
}

static VALUE
enc_new(rb_encoding *encoding)
{
    VALUE enc = Data_Wrap_Struct(rb_cEncoding, enc_mark, 0, encoding);
    encoding->auxiliary_data = (void *)enc;
    return enc;
}

VALUE
rb_enc_from_encoding(rb_encoding *encoding)
{
    if (!encoding) return Qnil;
    if (enc_initialized_p(encoding))
	return ENC_FROM_ENCODING(encoding);
    return enc_new(encoding);
}

static int
enc_check_encoding(VALUE obj)
{
    int index;
    rb_encoding *enc;

    if (SPECIAL_CONST_P(obj) || BUILTIN_TYPE(obj) != T_DATA ||
	RDATA(obj)->dmark != enc_mark) {
	return -1;
    }
    enc = (rb_encoding*)RDATA(obj)->data;
    index = rb_enc_to_index(enc);
    if (rb_enc_from_index(index) != enc)
	return -1;
    if (enc_autoload_p(enc)) {
	index = load_encoding(enc->name);
    }
    return index;
}

int
rb_to_encoding_index(VALUE enc)
{
    int idx;

    idx = enc_check_encoding(enc);
    if (idx >= 0) {
	return idx;
    }
    else if (NIL_P(enc = rb_check_string_type(enc))) {
	return -1;
    }
    else {
	return rb_enc_find_index(StringValueCStr(enc));
    }
}

rb_encoding *
rb_to_encoding(VALUE enc)
{
    int idx;

    idx = enc_check_encoding(enc);
    if (idx >= 0) return RDATA(enc)->data;
    if ((idx = rb_enc_find_index(StringValueCStr(enc))) < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    }
    return rb_enc_from_index(idx);
}

void
rb_gc_mark_encodings(void)
{
    int i;
    for (i = 0; i < enc_table.count; ++i) {
	rb_encoding *enc = enc_table.list[i].enc;
	if (enc && enc_initialized_p(enc)) {
	    rb_gc_mark(ENC_FROM_ENCODING(enc));
	}
    }
}

static int
enc_table_expand(int newsize)
{
    struct rb_encoding_entry *ent;
    int count = newsize;

    if (enc_table.size >= newsize) return newsize;
    newsize = (newsize + 7) / 8 * 8;
    ent = realloc(enc_table.list, sizeof(*enc_table.list) * newsize);
    if (!ent) return -1;
    memset(ent + enc_table.size, 0, sizeof(*ent)*(newsize - enc_table.size));
    enc_table.list = ent;
    enc_table.size = newsize;
    return count;
}

static int
enc_register_at(int index, const char *name, rb_encoding *encoding)
{
    struct rb_encoding_entry *ent = &enc_table.list[index];
    void *obj = ENC_UNINITIALIZED;

    if (!ent->name) {
	ent->name = name = strdup(name);
    }
    else if (STRCASECMP(name, ent->name)) {
	return -1;
    }
    if (!ent->enc) {
	ent->enc = malloc(sizeof(rb_encoding));
    }
    else {
	obj = ent->enc->auxiliary_data;
    }
    if (encoding) {
	*ent->enc = *encoding;
    }
    else {
	memset(ent->enc, 0, sizeof(*ent->enc));
    }
    encoding = ent->enc;
    encoding->name = name;
    encoding->ruby_encoding_index = index;
    st_insert(enc_table.names, (st_data_t)name, (st_data_t)index);
    if (obj != ENC_UNINITIALIZED) {
	encoding->auxiliary_data = obj;
    }
    else if (rb_cEncoding) {
	/* initialize encoding data */
	enc_new(encoding);
    }
    else {
	encoding->auxiliary_data = ENC_UNINITIALIZED;
    }
    return index;
}

static int
enc_register(const char *name, rb_encoding *encoding)
{
    int index = enc_table.count;

    if ((index = enc_table_expand(index + 1)) < 0) return -1;
    enc_table.count = index;
    return enc_register_at(index - 1, name, encoding);
}

static void set_encoding_const(const char *, rb_encoding *);
int rb_enc_registered(const char *name);

int
rb_enc_register(const char *name, rb_encoding *encoding)
{
    int index = rb_enc_registered(name);

    if (index >= 0) {
	rb_encoding *oldenc = rb_enc_from_index(index);
	if (STRCASECMP(name, rb_enc_name(oldenc))) {
	    index = enc_register(name, encoding);
	}
	else if (!enc_autoload_p(oldenc) ||
		 (enc_initialized_p(oldenc) &&
		  !ENC_DUMMY_P(ENC_FROM_ENCODING(oldenc)))) {
	    enc_register_at(index, name, encoding);
	}
	else {
	    rb_raise(rb_eArgError, "encoding %s is already registered", name);
	}
    }
    else {
	index = enc_register(name, encoding);
	set_encoding_const(name, rb_enc_from_index(index));
    }
    return index;
}

#ifndef NO_ENCDB_H
static void
encdb_declare(const char *name)
{
    int idx = rb_enc_registered(name);
    if (idx < 0) {
	idx = enc_register(name, 0);
    }
    set_encoding_const(name, rb_enc_from_index(idx));
}
#endif

static void
enc_check_duplication(const char *name)
{
    if (rb_enc_registered(name) >= 0) {
	rb_raise(rb_eArgError, "encoding %s is already registered", name);
    }
}

static VALUE
set_base_encoding(int index, rb_encoding *base)
{
    VALUE enc = rb_enc_from_encoding(enc_table.list[index].enc);

    rb_ivar_set(enc, id_base_encoding, rb_enc_from_encoding(base));
    if (rb_enc_dummy_p(base)) ENC_SET_DUMMY(enc);
    return enc;
}

int
rb_enc_replicate(const char *name, rb_encoding *encoding)
{
    int idx;

    enc_check_duplication(name);
    idx = enc_register(name, encoding);
    set_base_encoding(idx, encoding);
    set_encoding_const(name, rb_enc_from_index(idx));
    return idx;
}

#ifndef NO_ENCDB_H
static int
enc_replicate(int idx, const char *name, rb_encoding *origenc)
{
    if (idx < 0) {
	idx = enc_register(name, origenc);
    }
    else {
	idx = enc_register_at(idx, name, origenc);
    }
    if (idx >= 0) {
	set_base_encoding(idx, origenc);
	set_encoding_const(name, rb_enc_from_index(idx));
    }
    return idx;
}

static int
encdb_replicate(const char *name, const char *orig)
{
    int origidx = rb_enc_registered(orig);
    int idx = rb_enc_registered(name);

    if (origidx < 0) {
	origidx = enc_register(orig, 0);
    }
    return enc_replicate(idx, name, rb_enc_from_index(origidx));
}
#endif

int
rb_define_dummy_encoding(const char *name)
{
    int index = rb_enc_replicate(name, rb_ascii8bit_encoding());
    VALUE enc = rb_enc_from_encoding(enc_table.list[index].enc);

    ENC_SET_DUMMY(enc);
    return index;
}

#ifndef NO_ENCDB_H
static int
encdb_dummy(const char *name)
{
    int index = enc_replicate(rb_enc_registered(name), name,
			      rb_ascii8bit_encoding());
    VALUE enc = rb_enc_from_encoding(enc_table.list[index].enc);

    ENC_SET_DUMMY(enc);
    return index;
}
#endif
#endif // WITH_OBJC

int
rb_enc_dummy_p(rb_encoding *enc)
{
#if WITH_OBJC
    return Qfalse;
#else
    VALUE encoding = rb_enc_from_encoding(enc);
    return ENC_DUMMY_P(encoding);
#endif
}

/*
 * call-seq:
 *   enc.dummy? => true or false
 *
 * Returns true for dummy encodings.
 * A dummy encoding is an encoding for which character handling is not properly
 * implemented.
 * It is used for stateful encodings.
 *
 *   Encoding::ISO_2022_JP.dummy?       #=> true
 *   Encoding::UTF_8.dummy?             #=> false
 *
 */
static VALUE
enc_dummy_p(VALUE enc)
{
    return rb_enc_dummy_p(rb_to_encoding(enc)) ? Qtrue : Qfalse;
}

#if !WITH_OBJC
static int
enc_alias(const char *alias, int idx)
{
    alias = strdup(alias);
    st_insert(enc_table.names, (st_data_t)alias, (st_data_t)idx);
    set_encoding_const(alias, rb_enc_from_index(idx));
    return idx;
}

int
rb_enc_alias(const char *alias, const char *orig)
{
    int idx;

    enc_check_duplication(alias);
    if (!enc_table.list) {
	rb_enc_init();
    }
    if ((idx = rb_enc_find_index(orig)) < 0) {
	return -1;
    }
    return enc_alias(alias, idx);
}

#ifndef NO_ENCDB_H
static int
encdb_alias(const char *alias, const char *orig)
{
    int idx = rb_enc_registered(orig);

    if (idx < 0) {
	idx = enc_register(orig, 0);
    }
    return enc_alias(alias, idx);
}
#endif

enum {
    ENCINDEX_ASCII,
    ENCINDEX_UTF_8,
    ENCINDEX_US_ASCII,
    ENCINDEX_BUILTIN_MAX
};

extern rb_encoding OnigEncodingUTF_8;
extern rb_encoding OnigEncodingUS_ASCII;

void
rb_enc_init(void)
{
    enc_table_expand(ENCODING_COUNT + 1);
    if (!enc_table.names) {
	enc_table.names = st_init_strcasetable();
	GC_ROOT(&enc_table.names);
    }
#define ENC_REGISTER(enc) enc_register_at(ENCINDEX_##enc, rb_enc_name(&OnigEncoding##enc), &OnigEncoding##enc)
    ENC_REGISTER(ASCII);
    ENC_REGISTER(UTF_8);
    ENC_REGISTER(US_ASCII);
#undef ENC_REGISTER
    enc_table.count = ENCINDEX_BUILTIN_MAX;
}

rb_encoding *
rb_enc_from_index(int index)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    if (index < 0 || enc_table.count <= index) {
	return 0;
    }
    return enc_table.list[index].enc;
}

int
rb_enc_registered(const char *name)
{
    st_data_t idx = 0;

    if (!name) return -1;
    if (!enc_table.list) return -1;
    if (st_lookup(enc_table.names, (st_data_t)name, &idx)) {
	return (int)idx;
    }
    return -1;
}

static VALUE
require_enc(VALUE enclib)
{
    return rb_require_safe(enclib, rb_safe_level());
}

static int
load_encoding(const char *name)
{
    VALUE enclib = rb_sprintf("enc/%s", name);
    VALUE verbose = ruby_verbose;
    VALUE debug = ruby_debug;
    VALUE loaded;
    char *s = RSTRING_PTR(enclib) + 4, *e = RSTRING_END(enclib);
    int idx;

    while (s < e) {
	if (!ISALNUM(*s)) *s = '_';
	else if (ISUPPER(*s)) *s = TOLOWER(*s);
	++s;
    }
    OBJ_FREEZE(enclib);
    ruby_verbose = Qfalse;
    ruby_debug = Qfalse;
    loaded = rb_protect(require_enc, enclib, 0);
    ruby_verbose = verbose;
    ruby_debug = debug;
    rb_set_errinfo(Qnil);
    if (NIL_P(loaded)) return -1;
    if ((idx = rb_enc_registered(name)) < 0) return -1;
    if (enc_autoload_p(enc_table.list[idx].enc)) return -1;
    return idx;
}

int
rb_enc_find_index(const char *name)
{
    int i = rb_enc_registered(name), b;
    rb_encoding *enc;
    VALUE base;

    if (i < 0) {
	i = load_encoding(name);
    }
    else if (enc_autoload_p(enc = rb_enc_from_index(i))) {
	if (enc_initialized_p(enc) &&
	    (base = enc_base_encoding(ENC_FROM_ENCODING(enc)), !NIL_P(base))) {
	    if ((b = enc_check_encoding(base)) < 0) {
		goto failed;
	    }
	    enc_register_at(i, rb_enc_name(enc), rb_enc_from_index(b));
	}
	else {
	    i = load_encoding(rb_enc_name(enc));
	    if (i < 0) {
	      failed:
		rb_warn("failed to load encoding (%s); use ASCII-8BIT instead",
			name);
		return 0;
	    }
	}
    }
    return i;
}

rb_encoding *
rb_enc_find(const char *name)
{
    int idx = rb_enc_find_index(name);
    if (idx < 0) idx = 0;
    return rb_enc_from_index(idx);
}

static inline int
enc_capable(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) return Qfalse;
    switch (/*BUILTIN_*/TYPE(obj)) {
      case T_STRING:
      case T_REGEXP:
      case T_FILE:
	return Qtrue;
      case T_DATA:
	if (RDATA(obj)->dmark == enc_mark) return Qtrue;
      default:
	return Qfalse;
    }
}

static void
enc_check_capable(VALUE x)
{
    if (!enc_capable(x)) {
	const char *etype;

	if (NIL_P(x)) {
	    etype = "nil";
	}
	else if (FIXNUM_P(x)) {
	    etype = "Fixnum";
	}
	else if (SYMBOL_P(x)) {
	    etype = "Symbol";
	}
	else if (rb_special_const_p(x)) {
	    etype = RSTRING_PTR(rb_obj_as_string(x));
	}
	else {
	    etype = rb_obj_classname(x);
	}
	rb_raise(rb_eTypeError, "wrong argument type %s (not encode capable)", etype);
    }
}
#endif

ID
rb_id_encoding(void)
{
    if (!id_encoding) {
	id_encoding = rb_intern("encoding");
    }
    return id_encoding;
}

#if !WITH_OBJC
int
rb_enc_internal_get_index(VALUE obj)
{
    int i;

    i = ENCODING_GET_INLINED(obj);
    if (i == ENCODING_INLINE_MAX) {
	VALUE iv;

	iv = rb_ivar_get(obj, rb_id_encoding());
	i = NUM2INT(iv);
    }
    return i;
}

void
rb_enc_internal_set_index(VALUE obj, int idx)
{
    if (idx < ENCODING_INLINE_MAX) {
	ENCODING_SET_INLINED(obj, idx);
	return;
    }
    ENCODING_SET_INLINED(obj, ENCODING_INLINE_MAX);
    rb_ivar_set(obj, rb_id_encoding(), INT2NUM(idx));
    return;
}

void
rb_enc_associate_index(VALUE obj, int idx)
{
    enc_check_capable(obj);
    if (rb_enc_get_index(obj) == idx)
    	return;
    if (!ENC_CODERANGE_ASCIIONLY(obj) ||
	!rb_enc_asciicompat(rb_enc_from_index(idx))) {
	ENC_CODERANGE_CLEAR(obj);
    }
    rb_enc_internal_set_index(obj, idx);
}

void
rb_enc_associate(VALUE obj, rb_encoding *enc)
{
    rb_enc_associate_index(obj, rb_enc_to_index(enc));
}

int
rb_enc_get_index(VALUE obj)
{
    if (!enc_capable(obj)) return -1;
    return rb_enc_internal_get_index(obj);
}

rb_encoding*
rb_enc_get(VALUE obj)
{
    return rb_enc_from_index(rb_enc_get_index(obj));
}

rb_encoding*
rb_enc_check(VALUE str1, VALUE str2)
{
    rb_encoding *enc = rb_enc_compatible(str1, str2);
    if (!enc)
	rb_raise(rb_eArgError, "character encodings differ: %s and %s",
		 rb_enc_name(rb_enc_get(str1)),
		 rb_enc_name(rb_enc_get(str2)));
    return enc;
}
#endif

rb_encoding*
rb_enc_compatible(VALUE str1, VALUE str2)
{
#if WITH_OBJC
    /* TODO */
    rb_encoding *enc = rb_enc_get(str1);
    if (enc == rb_enc_get(str2))
	return enc;
    return NULL;
#else
    int idx1, idx2;
    rb_encoding *enc1, *enc2;

    idx1 = rb_enc_get_index(str1);
    idx2 = rb_enc_get_index(str2);

    if (idx1 < 0 || idx2 < 0)
        return 0;

    if (idx1 == idx2) {
	return rb_enc_from_index(idx1);
    }
    enc1 = rb_enc_from_index(idx1);
    enc2 = rb_enc_from_index(idx2);

    if (TYPE(str2) == T_STRING && RSTRING_LEN(str2) == 0)
	return enc1;
    if (TYPE(str1) == T_STRING && RSTRING_LEN(str1) == 0)
	return enc2;
    if (!rb_enc_asciicompat(enc1) || !rb_enc_asciicompat(enc2)) {
	return 0;
    }

    if (BUILTIN_TYPE(str1) != T_STRING) {
	VALUE tmp = str1;
	int idx0 = idx1;
	str1 = str2;
	str2 = tmp;
	idx1 = idx2;
	idx2 = idx0;
    }
    if (BUILTIN_TYPE(str1) == T_STRING) {
	int cr1, cr2;

	cr1 = rb_enc_str_coderange(str1);
	if (BUILTIN_TYPE(str2) == T_STRING) {
	    cr2 = rb_enc_str_coderange(str2);
	    if (cr1 != cr2) {
		/* may need to handle ENC_CODERANGE_BROKEN */
		if (cr1 == ENC_CODERANGE_7BIT) return enc2;
		if (cr2 == ENC_CODERANGE_7BIT) return enc1;
	    }
	    if (cr2 == ENC_CODERANGE_7BIT) {
		if (idx1 == 0) return enc2;
		return enc1;
	    }
	}
	if (cr1 == ENC_CODERANGE_7BIT)
	    return enc2;
    }
    return 0;
#endif
}

#if !WITH_OBJC
void
rb_enc_copy(VALUE obj1, VALUE obj2)
{
    rb_enc_associate_index(obj1, rb_enc_get_index(obj2));
}
#endif

/*
 *  call-seq:
 *     obj.encoding   => encoding
 *
 *  Returns the Encoding object that represents the encoding of obj.
 */

VALUE
rb_obj_encoding(VALUE obj)
{
    rb_encoding *enc = rb_enc_get(obj);
    if (!enc) {
	rb_raise(rb_eTypeError, "unknown encoding");
    }
    return rb_enc_from_encoding(enc);
}

#if !WITH_OBJC
int
rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n = ONIGENC_PRECISE_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    if (MBCLEN_CHARFOUND_P(n) && MBCLEN_CHARFOUND_LEN(n) <= e-p)
        return MBCLEN_CHARFOUND_LEN(n);
    else {
        int min = rb_enc_mbminlen(enc);
        return min <= e-p ? min : e-p;
    }
}

int
rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n;
    if (e <= p)
        return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(1);
    n = ONIGENC_PRECISE_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    if (e-p < n)
        return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(n-(e-p));
    return n;
}

int
rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc)
{
    int c, l;
    if (e <= p)
        return -1;
    if (rb_enc_asciicompat(enc)) {
        c = (unsigned char)*p;
        if (!ISASCII(c))
            return -1;
        if (len) *len = 1;
        return c;
    }
    l = rb_enc_precise_mbclen(p, e, enc);
    if (!MBCLEN_CHARFOUND_P(l))
        return -1;
    c = rb_enc_mbc_to_codepoint(p, e, enc);
    if (!rb_enc_isascii(c, enc))
        return -1;
    if (len) *len = l;
    return c;
}

int
rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    int r;
    if (e <= p)
        rb_raise(rb_eArgError, "empty string");
    r = rb_enc_precise_mbclen(p, e, enc);
    if (MBCLEN_CHARFOUND_P(r))
        return rb_enc_mbc_to_codepoint(p, e, enc);
    else
	rb_raise(rb_eArgError, "invalid mbstring sequence");
}

int
rb_enc_codelen(int c, rb_encoding *enc)
{
    int n = ONIGENC_CODE_TO_MBCLEN(enc,c);
    if (n == 0) {
	rb_raise(rb_eArgError, "invalid codepoint 0x%x", c);
    }
    return n;
}

int
rb_enc_toupper(int c, rb_encoding *enc)
{
    return (ONIGENC_IS_ASCII_CODE(c)?ONIGENC_ASCII_CODE_TO_UPPER_CASE(c):(c));
}

int
rb_enc_tolower(int c, rb_encoding *enc)
{
    return (ONIGENC_IS_ASCII_CODE(c)?ONIGENC_ASCII_CODE_TO_LOWER_CASE(c):(c));
}
#endif

/*
 * call-seq:
 *   enc.inspect => string
 *
 * Returns a string which represents the encoding for programmers.
 *
 *   Encoding::UTF_8.inspect       #=> "#<Encoding:UTF-8>"
 *   Encoding::ISO_2022_JP.inspect #=> "#<Encoding:ISO-2022-JP (dummy)>"
 */
static VALUE
enc_inspect(VALUE self)
{
#if WITH_OBJC
    char buffer[512];
    VALUE enc_name;
    long n;

    enc_name = (VALUE)CFStringGetNameOfEncoding(rb_enc_to_enc(self));
    
    n = snprintf(buffer, sizeof buffer, "#<%s:%s>", rb_obj_classname(self),
	RSTRING_CPTR(enc_name));

    return rb_str_new(buffer, n);
#else
    VALUE str = rb_sprintf("#<%s:%s%s>", rb_obj_classname(self),
		      rb_enc_name((rb_encoding*)DATA_PTR(self)),
		      (ENC_DUMMY_P(self) ? " (dummy)" : ""));
    ENCODING_CODERANGE_SET(str, rb_usascii_encindex(), ENC_CODERANGE_7BIT);
    return str;
#endif
}

/*
 * call-seq:
 *   enc.name => string
 *
 * Returns the name of the encoding.
 *
 *   Encoding::UTF_8.name       => "UTF-8"
 */
static VALUE
enc_name(VALUE self)
{
#if WITH_OBJC
    return (VALUE)CFStringConvertEncodingToIANACharSetName(rb_enc_to_enc(self));
#else
    return rb_usascii_str_new2(rb_enc_name((rb_encoding*)DATA_PTR(self)));
#endif
}

static VALUE
enc_base_encoding(VALUE self)
{
    return rb_attr_get(self, id_base_encoding);
}

/*
 * call-seq:
 *   Encoding.list => [enc1, enc2, ...]
 *
 * Returns the list of loaded encodings.
 *
 *   Encoding.list
 *   => [#<Encoding:ASCII-8BIT>, #<Encoding:UTF-8>,
 *       #<Encoding:ISO-2022-JP (dummy)>]
 *
 *   Encoding.find("US-ASCII")
 *   => #<Encoding:US-ASCII>
 *
 *   Encoding.list
 *   => [#<Encoding:ASCII-8BIT>, #<Encoding:UTF-8>,
 *       #<Encoding:US-ASCII>, #<Encoding:ISO-2022-JP (dummy)>]
 *
 */

static VALUE
enc_list(VALUE klass)
{
#if WITH_OBJC
    VALUE ary;
    const CFStringEncoding *e;

    ary = rb_ary_new();
    e = CFStringGetListOfAvailableEncodings();
    while (e != NULL && *e != kCFStringEncodingInvalidId) {
	rb_ary_push(ary, enc_make(e));
	e++;
    }
#else
    VALUE ary = rb_ary_new2(enc_table.count);
    int i;
    for (i = 0; i < enc_table.count; ++i) {
	rb_encoding *enc = enc_table.list[i].enc;
	if (enc) {
	    rb_ary_push(ary, rb_enc_from_encoding(enc));
	}
    }
#endif
    return ary;
}

/*
 * call-seq:
 *   Encoding.find(string) => enc
 *   Encoding.find(symbol) => enc
 *
 * Search the encoding with specified <i>name</i>.
 * <i>name</i> should be a string or symbol.
 *
 *   Encoding.find("US-ASCII")  => #<Encoding:US-ASCII>
 *   Encoding.find(:Shift_JIS)  => #<Encoding:Shift_JIS>
 *
 */
static VALUE
enc_find2(VALUE enc)
{
    CFStringEncoding e;
    
    e = CFStringConvertIANACharSetNameToEncoding((CFStringRef)StringValue(enc));
    if (e == kCFStringEncodingInvalidId)
	return Qnil;
    return enc_make(&e);
}

static VALUE
enc_find(VALUE klass, VALUE enc)
{
#if WITH_OBJC
    VALUE e = enc_find2(enc);
    if (e == Qnil)
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    return e;
#else
    int idx;

    StringValue(enc);
    if (!rb_enc_asciicompat(rb_enc_get(enc))) {
	rb_raise(rb_eArgError, "invalid name encoding (non ASCII)");
    }
    idx = rb_enc_find_index(StringValueCStr(enc));
    if (idx < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    }
    return rb_enc_from_encoding(rb_enc_from_index(idx));
#endif
}

/*
 * call-seq:
 *   Encoding.compatible?(str1, str2) => enc or nil
 *
 * Checks the compatibility of two strings.
 * If they are compatible, means concatenatable, 
 * returns an encoding which the concatinated string will be.
 * If they are not compatible, nil is returned.
 *
 *   Encoding.compatible?("\xa1".force_encoding("iso-8859-1"), "b")
 *   => #<Encoding:ISO-8859-1>
 *
 *   Encoding.compatible?(
 *     "\xa1".force_encoding("iso-8859-1"),
 *     "\xa1\xa1".force_encoding("euc-jp"))
 *   => nil
 *
 */
static VALUE
enc_compatible_p(VALUE klass, VALUE str1, VALUE str2)
{
    rb_encoding *enc = rb_enc_compatible(str1, str2);
    VALUE encoding = Qnil;
    if (!enc || !(encoding = rb_enc_from_encoding(enc)))
	encoding = Qnil;
    return encoding;
}

/* :nodoc: */
static VALUE
enc_dump(int argc, VALUE *argv, VALUE self)
{
    rb_scan_args(argc, argv, "01", 0);
    return enc_name(self);
}

/* :nodoc: */
static VALUE
enc_load(VALUE klass, VALUE str)
{
    return enc_find(klass, str);
}

#if !WITH_OBJC
rb_encoding *
rb_ascii8bit_encoding(void)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    return enc_table.list[0].enc;
}

rb_encoding *
rb_utf8_encoding(void)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    return enc_table.list[ENCINDEX_UTF_8].enc;
}

rb_encoding *
rb_usascii_encoding(void)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    return enc_table.list[ENCINDEX_US_ASCII].enc;
}

int
rb_usascii_encindex(void)
{
    return ENCINDEX_US_ASCII;
}

rb_encoding *
rb_locale_encoding(void)
{
    VALUE charmap = rb_locale_charmap(rb_cEncoding);
    int idx;

    if (NIL_P(charmap))
        idx = rb_enc_find_index("US-ASCII");
    else
        idx = rb_enc_find_index(StringValueCStr(charmap));
    if (idx < 0)
        return rb_ascii8bit_encoding();

    return rb_enc_from_index(idx);
}

static int default_external_index;

rb_encoding *
rb_default_external_encoding(void)
{
    return rb_enc_from_index(default_external_index);
}

VALUE
rb_enc_default_external(void)
{
    return rb_enc_from_encoding(rb_default_external_encoding());
}
#endif

#if WITH_OBJC
static rb_encoding *default_external;
    
rb_encoding *
rb_default_external_encoding(void)
{
    return default_external;
}

VALUE
rb_enc_default_external(void)
{
    return enc_make(default_external);
}
#endif

/*
 * call-seq:
 *   Encoding.default_external => enc
 *
 * Returns default external encoding.
 *
 * It is initialized by the locale or -E option.
 */
static VALUE
get_default_external(VALUE klass)
{
    return rb_enc_default_external();
}

void
rb_enc_set_default_external(VALUE encoding)
{
#if WITH_OBJC
    default_external = rb_enc_to_enc_ptr(encoding);
#else
    default_external_index = rb_enc_to_index(rb_to_encoding(encoding));
#endif
}

/*
 * call-seq:
 *   Encoding.locale_charmap => string
 *
 * Returns the locale charmap name.
 *
 *   Debian GNU/Linux
 *     LANG=C
 *       Encoding.locale_charmap  => "ANSI_X3.4-1968"
 *     LANG=ja_JP.EUC-JP
 *       Encoding.locale_charmap  => "EUC-JP"
 *
 *   SunOS 5
 *     LANG=C
 *       Encoding.locale_charmap  => "646"
 *     LANG=ja
 *       Encoding.locale_charmap  => "eucJP"
 *
 */
VALUE
rb_locale_charmap(VALUE klass)
{
#if WITH_OBJC
    CFStringEncoding enc = CFStringGetSystemEncoding();
    return (VALUE)CFStringConvertEncodingToIANACharSetName(enc);
#elif defined NO_LOCALE_CHARMAP
    return rb_usascii_str_new2("ASCII-8BIT");
#elif defined HAVE_LANGINFO_H
    char *codeset;
    codeset = nl_langinfo(CODESET);
    return rb_usascii_str_new2(codeset);
#elif defined _WIN32
    return rb_sprintf("CP%d", GetACP());
#else
    return Qnil;
#endif
}

#if !WITH_OBJC
static void
set_encoding_const(const char *name, rb_encoding *enc)
{
    VALUE encoding = rb_enc_from_encoding(enc);
    char *s = (char *)name;
    int haslower = 0, hasupper = 0, valid = 0;

    if (ISDIGIT(*s)) return;
    if (ISUPPER(*s)) {
	hasupper = 1;
	while (*++s && (ISALNUM(*s) || *s == '_')) {
	    if (ISLOWER(*s)) haslower = 1;
	}
    }
    if (!*s) {
	valid = 1;
	rb_define_const(rb_cEncoding, name, encoding);
    }
    if (!valid || haslower) {
	int len = strlen(name) + 1;
	if (!haslower || !hasupper) {
	    do {
		if (ISLOWER(*s)) haslower = 1;
		if (ISUPPER(*s)) hasupper = 1;
	    } while (*++s && (!haslower || !hasupper));
	}
	MEMCPY(s = ALLOCA_N(char, len), name, char, len);
	name = s;
	if (!valid) {
	    if (ISLOWER(*s)) *s = ONIGENC_ASCII_CODE_TO_UPPER_CASE((int)*s);
	    for (; *s; ++s) {
		if (!ISALNUM(*s)) *s = '_';
	    }
	    if (hasupper) {
		rb_define_const(rb_cEncoding, name, encoding);
	    }
	}
	if (haslower) {
	    for (s = (char *)name; *s; ++s) {
		if (ISLOWER(*s)) *s = ONIGENC_ASCII_CODE_TO_UPPER_CASE((int)*s);
	    }
	    rb_define_const(rb_cEncoding, name, encoding);
	}
    }
}

static int
rb_enc_name_list_i(st_data_t name, st_data_t idx, st_data_t arg)
{
    VALUE ary = (VALUE)arg;
    VALUE str = rb_usascii_str_new2((char *)name);
    OBJ_FREEZE(str);
    rb_ary_push(ary, str);
    return ST_CONTINUE;
}
#endif

/*
 * call-seq:
 *   Encoding.name_list => ["enc1", "enc2", ...]
 *
 * Returns the list of available encoding names.
 *
 *   Encoding.name_list
 *   => ["US-ASCII", "ASCII-8BIT", "UTF-8",
 *       "ISO-8859-1", "Shift_JIS", "EUC-JP",
 *       "Windows-31J",
 *       "BINARY", "CP932", "eucJP"]
 *
 * This list doesn't include dummy encodings.
 *
 */

static VALUE
rb_enc_name_list(VALUE klass)
{
#if WITH_OBJC
    VALUE ary, list;
    long i, count;

    ary = rb_ary_new();
    list = enc_list(klass);
    for (i = 0, count = RARRAY_LEN(list); i < count; i++)
	rb_ary_push(ary, enc_name(RARRAY_AT(list, i)));
#else
    VALUE ary = rb_ary_new2(enc_table.names->num_entries);
    st_foreach(enc_table.names, rb_enc_name_list_i, (st_data_t)ary);
#endif
    return ary;
}

#if !WITH_OBJC
static int
rb_enc_aliases_enc_i(st_data_t name, st_data_t orig, st_data_t arg)
{
    VALUE *p = (VALUE *)arg;
    VALUE aliases = p[0], ary = p[1];
    int idx = (int)orig;
    VALUE key, str = rb_ary_entry(ary, idx);

    if (NIL_P(str)) {
	rb_encoding *enc = rb_enc_from_index(idx);

	if (STRCASECMP((char*)name, rb_enc_name(enc)) == 0) {
	    return ST_CONTINUE;
	}
	str = rb_usascii_str_new2(rb_enc_name(enc));
	OBJ_FREEZE(str);
	rb_ary_store(ary, idx, str);
    }
    key = rb_usascii_str_new2((char *)name);
    OBJ_FREEZE(key);
    rb_hash_aset(aliases, key, str);
    return ST_CONTINUE;
}
#endif

/*
 * call-seq:
 *   Encoding.aliases => {"alias1" => "orig1", "alias2" => "orig2", ...}
 *
 * Returns the hash of available encoding alias and original encoding name.
 *
 *   Encoding.aliases
 *   => {"BINARY"=>"ASCII-8BIT", "ASCII"=>"US-ASCII", "ANSI_X3.4-1986"=>"US-ASCII",
 *       "SJIS"=>"Shift_JIS", "eucJP"=>"EUC-JP", "CP932"=>"Windows-31J"}
 *
 */

static VALUE
rb_enc_aliases(VALUE klass)
{
#if WITH_OBJC
    /* TODO: the CFString IANA <-> charset code does support aliases, we should
     * find a way to return them here. 
     */
    return rb_hash_new();
#else
    VALUE aliases[2];
    aliases[0] = rb_hash_new();
    aliases[1] = rb_ary_new();
    st_foreach(enc_table.names, rb_enc_aliases_enc_i, (st_data_t)aliases);
    return aliases[0];
#endif
}

VALUE
rb_enc_name2(rb_encoding *enc)
{
    CFStringRef str;
    if (enc != NULL 
	&& (str = CFStringConvertEncodingToIANACharSetName(*enc)) != NULL)
	return str;
    return Qnil;
}

const char *
rb_enc_name(rb_encoding *enc)
{
    CFStringRef str = rb_enc_name2(enc);
    return str == Qnil ? NULL : RSTRING_CPTR(str);
}

long 
rb_enc_mbminlen(rb_encoding *enc)
{
    return rb_enc_mbmaxlen(enc);
}

long
rb_enc_mbmaxlen(rb_encoding *enc)
{
    return CFStringGetMaximumSizeForEncoding(1, *enc);
}

rb_encoding *
rb_enc_find(const char *name)
{
    return rb_enc_find2(rb_str_new2(name));
}

rb_encoding *
rb_enc_find2(VALUE name)
{
    VALUE e = enc_find2(name);
    return e == Qnil ? NULL : rb_enc_to_enc_ptr(e);
}

rb_encoding *
rb_enc_get(VALUE obj)
{
    int type = TYPE(obj);
    if (type == T_STRING) {
	CFStringEncoding enc = CFStringGetFastestEncoding((CFStringRef)obj);
	if (enc == kCFStringEncodingInvalidId)
	    return NULL;
	return rb_enc_to_enc_ptr(enc_make(&enc));
    }
    else {
	/* TODO */
	return NULL;
    }
}

rb_encoding *
rb_locale_encoding(void)
{
    CFStringEncoding enc = CFStringGetSystemEncoding();
    return rb_enc_to_enc_ptr(enc_make(&enc));
}

void
Init_Encoding(void)
{
    id_base_encoding = rb_intern("#base_encoding");

    rb_cEncoding = rb_define_class("Encoding", rb_cObject);
    rb_undef_alloc_func(rb_cEncoding);
    rb_define_method(rb_cEncoding, "to_s", enc_name, 0);
    rb_define_method(rb_cEncoding, "inspect", enc_inspect, 0);
    rb_define_method(rb_cEncoding, "name", enc_name, 0);
    rb_define_method(rb_cEncoding, "base_encoding", enc_base_encoding, 0);
    rb_define_method(rb_cEncoding, "dummy?", enc_dummy_p, 0);
    rb_define_singleton_method(rb_cEncoding, "list", enc_list, 0);
    rb_define_singleton_method(rb_cEncoding, "name_list", rb_enc_name_list, 0);
    rb_define_singleton_method(rb_cEncoding, "aliases", rb_enc_aliases, 0);
    rb_define_singleton_method(rb_cEncoding, "find", enc_find, 1);
    rb_define_singleton_method(rb_cEncoding, "compatible?", enc_compatible_p, 2);

    rb_define_method(rb_cEncoding, "_dump", enc_dump, -1);
    rb_define_singleton_method(rb_cEncoding, "_load", enc_load, 1);

    rb_define_singleton_method(rb_cEncoding, "default_external", get_default_external, 0);
    rb_define_singleton_method(rb_cEncoding, "locale_charmap", rb_locale_charmap, 0);

    enc_init_db();
}

/* locale insensitive functions */

#define ctype_test(c, ctype) \
    (rb_isascii(c) && ONIGENC_IS_ASCII_CODE_CTYPE((c), ctype))

int rb_isalnum(int c) { return ctype_test(c, ONIGENC_CTYPE_ALNUM); }
int rb_isalpha(int c) { return ctype_test(c, ONIGENC_CTYPE_ALPHA); }
int rb_isblank(int c) { return ctype_test(c, ONIGENC_CTYPE_BLANK); }
int rb_iscntrl(int c) { return ctype_test(c, ONIGENC_CTYPE_CNTRL); }
int rb_isdigit(int c) { return ctype_test(c, ONIGENC_CTYPE_DIGIT); }
int rb_isgraph(int c) { return ctype_test(c, ONIGENC_CTYPE_GRAPH); }
int rb_islower(int c) { return ctype_test(c, ONIGENC_CTYPE_LOWER); }
int rb_isprint(int c) { return ctype_test(c, ONIGENC_CTYPE_PRINT); }
int rb_ispunct(int c) { return ctype_test(c, ONIGENC_CTYPE_PUNCT); }
int rb_isspace(int c) { return ctype_test(c, ONIGENC_CTYPE_SPACE); }
int rb_isupper(int c) { return ctype_test(c, ONIGENC_CTYPE_UPPER); }
int rb_isxdigit(int c) { return ctype_test(c, ONIGENC_CTYPE_XDIGIT); }

int
rb_tolower(int c)
{
    return rb_isascii(c) ? ONIGENC_ASCII_CODE_TO_LOWER_CASE(c) : c;
}

int
rb_toupper(int c)
{
    return rb_isascii(c) ? ONIGENC_ASCII_CODE_TO_UPPER_CASE(c) : c;
}

