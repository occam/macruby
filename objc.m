/*  
 *  Copyright (c) 2008, Apple Inc. All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *  1.  Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *  2.  Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *  3.  Neither the name of Apple Inc. ("Apple") nor the names of
 *      its contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR
 *  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 *  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 *  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 *  IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 */

#include "ruby/ruby.h"
#include "ruby/node.h"
#include "ruby/encoding.h"
#include <unistd.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <Foundation/Foundation.h>
#if HAVE_BRIDGESUPPORT_FRAMEWORK
# include <BridgeSupport/BridgeSupport.h>
#else
# include "bs.h"
#endif
#include "vm_core.h"
#include "vm.h"

typedef struct {
    bs_element_type_t type;
    void *value;
    VALUE klass;
    ffi_type *ffi_type;
} bs_element_boxed_t;

typedef struct {
    char *name;
    struct st_table *cmethods;
    struct st_table *imethods;
} bs_element_indexed_class_t;

static VALUE rb_cBoxed;
static ID rb_ivar_type;

static VALUE bs_const_magic_cookie = Qnil;
static VALUE rb_objc_class_magic_cookie = Qnil;

static struct st_table *bs_constants;
static struct st_table *bs_functions;
static struct st_table *bs_function_syms;
static struct st_table *bs_boxeds;
static struct st_table *bs_classes;
static struct st_table *bs_inf_prot_cmethods;
static struct st_table *bs_inf_prot_imethods;
static struct st_table *bs_cftypes;

#if 0
static char *
rb_objc_sel_to_mid(SEL selector, char *buffer, unsigned buffer_len)
{
    size_t s;
    char *p;

    s = strlcpy(buffer, (const char *)selector, buffer_len);

    p = buffer + s - 1;
    if (*p == ':')
	*p = '\0';

    p = buffer;
    while ((p = strchr(p, ':')) != NULL) {
	*p = '_';
	p++;
    }

    return buffer;
}
#endif

static inline const char *
rb_objc_skip_octype_modifiers(const char *octype)
{
    while (true) {
	switch (*octype) {
	    case _C_CONST:
	    case 'O': /* bycopy */
	    case 'n': /* in */
	    case 'o': /* out */
	    case 'N': /* inout */
	    case 'V': /* oneway */
		octype++;
		break;

	    default:
		return octype;
	}
    }
}

static inline const char *
__iterate_until(const char *type, char end)
{
    char begin;
    unsigned nested;

    begin = *type;
    nested = 0;

    do {
	type++;
	if (*type == begin) {
	    nested++;
	}
	else if (*type == end) {
	    if (nested == 0)
		return type;
	    nested--;
	}
    }
    while (YES);

    return NULL;
}

static const char *
rb_objc_get_first_type(const char *type, char *buf, size_t buf_len)
{
    const char *orig_type;
    const char *p;

    orig_type = type;

    type = rb_objc_skip_octype_modifiers(type);

    switch (*type) {
	case '\0':
	    return NULL;
	case _C_ARY_B:
	    type = __iterate_until(type, _C_ARY_E);
            break;
	case _C_STRUCT_B:
	    type = __iterate_until(type, _C_STRUCT_E);
 	    break;
	case _C_UNION_B:
	    type = __iterate_until(type, _C_UNION_E);
	    break;
	case _C_PTR:
	    type++;
	    buf[0] = _C_PTR;
	    buf_len -= 1;
	    return rb_objc_get_first_type(type, &buf[1], buf_len);
    }

    type++;
    p = type;
    while (*p >= '0' && *p <= '9') { p++; }

    if (buf != NULL) {
	size_t len = (long)(type - orig_type);
	assert(len < buf_len);
	strncpy(buf, orig_type, len);
	buf[len] = '\0';
    }

    return p;
}

static ffi_type *
fake_ary_ffi_type(size_t size, size_t align)
{
    static struct st_table *ary_ffi_types = NULL;
    ffi_type *type;
    unsigned i;

    assert(size > 0);

    if (ary_ffi_types == NULL) {
	ary_ffi_types = st_init_numtable();
	GC_ROOT(&ary_ffi_types);
    }

    if (st_lookup(ary_ffi_types, (st_data_t)size, (st_data_t *)&type))
	return type;

    type = (ffi_type *)malloc(sizeof(ffi_type));

    type->size = size;
    type->alignment = align;
    type->type = FFI_TYPE_STRUCT;
    type->elements = malloc(size * sizeof(ffi_type *));
  
    for (i = 0; i < size; i++)
	type->elements[i] = &ffi_type_uchar;

    st_insert(ary_ffi_types, (st_data_t)size, (st_data_t)type);

    return type;
}

static size_t
get_ffi_struct_size(ffi_type *type)
{
    ffi_type **p;
    size_t s;

    if (type->size > 0)
	return type->size;

    assert(type->type == FFI_TYPE_STRUCT);

    for (s = 0, p = &type->elements[0]; *p != NULL; p++)
	s += get_ffi_struct_size(*p);

    return s;
}

static ffi_type *
rb_objc_octype_to_ffitype(const char *octype)
{
    octype = rb_objc_skip_octype_modifiers(octype);

    if (bs_cftypes != NULL && st_lookup(bs_cftypes, (st_data_t)octype, NULL))
	octype = "@";

    switch (*octype) {
	case _C_ID:
	case _C_CLASS:
	case _C_SEL:
	case _C_CHARPTR:
	case _C_PTR:
	    return &ffi_type_pointer;

	case _C_BOOL:
	case _C_UCHR:
	    return &ffi_type_uchar;

	case _C_CHR:
	    return &ffi_type_schar;

	case _C_SHT:
	    return &ffi_type_sshort;

	case _C_USHT:
	    return &ffi_type_ushort;

	case _C_INT:
	    return &ffi_type_sint;

	case _C_UINT:
	    return &ffi_type_uint;

	case _C_LNG:
	    return sizeof(int) == sizeof(long) 
		? &ffi_type_sint : &ffi_type_slong;

#if defined(_C_LNG_LNG)
	case _C_LNG_LNG:
	    return &ffi_type_sint64;
#endif

	case _C_ULNG:
	    return sizeof(unsigned int) == sizeof(unsigned long) 
		? &ffi_type_uint : &ffi_type_ulong;

#if defined(_C_ULNG_LNG)
	case _C_ULNG_LNG:
	    return &ffi_type_uint64;
#endif

	case _C_FLT:
	    return &ffi_type_float;

	case _C_DBL:
	    return &ffi_type_double;

	case _C_ARY_B:
	{
#if __LP64__
	    unsigned long size, align;
#else
	    unsigned int size, align;
#endif

	    @try {
		NSGetSizeAndAlignment(octype, &size, &align);
	    }
	    @catch (id exception) {
		rb_raise(rb_eRuntimeError, "can't get size of type `%s': %s",
			 octype, [[exception description] UTF8String]);
            }

	    if (size > 0)
		return fake_ary_ffi_type(size, align);
	    break;
        }
	
	case _C_BFLD:
	{
	    char *type;
	    long lng;
	    size_t size;

	    type = (char *)octype;
	    lng  = strtol(type, &type, 10);

	    /* while next type is a bit field */
	    while (*type == _C_BFLD) {
		long next_lng;

		/* skip over _C_BFLD */
		type++;

		/* get next bit field length */
		next_lng = strtol(type, &type, 10);

		/* if spans next word then align to next word */
		if ((lng & ~31) != ((lng + next_lng) & ~31))
		    lng = (lng + 31) & ~31;

		/* increment running length */
		lng += next_lng;
	    }
	    size = (lng + 7) / 8;
	
	    if (size > 0) {	
		if (size == 1)
		    return &ffi_type_uchar;
		else if (size == 2)
		    return &ffi_type_ushort;
		else if (size <= 4)
		    return &ffi_type_uint;
		return fake_ary_ffi_type(size, 0);
	    }
	    break;
	}

	case _C_STRUCT_B:
	{
	    bs_element_boxed_t *bs_boxed;
	    if (st_lookup(bs_boxeds, (st_data_t)octype, 
			  (st_data_t *)&bs_boxed)) {
		bs_element_struct_t *bs_struct = 
		    (bs_element_struct_t *)bs_boxed->value;
		unsigned i;

		assert(bs_boxed->type == BS_ELEMENT_STRUCT);
		if (bs_boxed->ffi_type != NULL)
		    return bs_boxed->ffi_type;

		bs_boxed->ffi_type = (ffi_type *)malloc(sizeof(ffi_type));
		bs_boxed->ffi_type->size = 0;
		bs_boxed->ffi_type->alignment = 0;
		bs_boxed->ffi_type->type = FFI_TYPE_STRUCT;
		bs_boxed->ffi_type->elements = malloc(
	     	    (bs_struct->fields_count) * sizeof(ffi_type *));

		for (i = 0; i < bs_struct->fields_count; i++) {
		    bs_element_struct_field_t *field = &bs_struct->fields[i];
		    bs_boxed->ffi_type->elements[i] = 
			rb_objc_octype_to_ffitype(field->type);
		}
        
		bs_boxed->ffi_type->elements[bs_struct->fields_count] = NULL;

		{
		    /* Prepare a fake cif, to make sure critical things such 
		     * as the ffi_type size is set. 
		     */
		    ffi_cif cif;
		    ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 0, bs_boxed->ffi_type, 
				 NULL);
		    assert(bs_boxed->ffi_type->size > 0);
		}

		return bs_boxed->ffi_type;
	    }
	    break;
	}

	case _C_VOID:
	    return &ffi_type_void;
    }

    rb_raise(rb_eRuntimeError, "unrecognized octype `%s'", octype);

    return NULL;
}

static bool
rb_objc_rval_to_ocid(VALUE rval, void **ocval, bool force_nsnil)
{
    if (!rb_special_const_p(rval) && rb_objc_is_non_native(rval)) {
	*(id *)ocval = (id)rval;
	return true;
    }

    switch (TYPE(rval)) {
	case T_STRING:
	case T_ARRAY:
	case T_HASH:
	case T_OBJECT:
	    *(id *)ocval = (id)rval;
	    return true;

	case T_CLASS:
	case T_MODULE:
	    *(id *)ocval = (id)RCLASS_OCID(rval);
	    return true;

	case T_NIL:
	    if (force_nsnil) {
		static id snull = nil;
		if (snull == nil)
		    snull = [NSNull null];
		*(id *)ocval = snull;
	    }
	    else {
		*(id *)ocval = NULL;
	    }
	    return true;

	case T_TRUE:
	case T_FALSE:
	{
	    char v = RTEST(rval);
	    *(id *)ocval = (id)CFNumberCreate(NULL, kCFNumberCharType, &v);
	    CFMakeCollectable(*(id *)ocval);
	    return true;
	}

	case T_FLOAT:
	{
	    double v = RFLOAT_VALUE(rval);
	    *(id *)ocval = (id)CFNumberCreate(NULL, kCFNumberDoubleType, &v);
	    CFMakeCollectable(*(id *)ocval);
	    return true;
	}	

	case T_FIXNUM:
	case T_BIGNUM:
	{
	    if (FIXNUM_P(rval)) {
		long v = FIX2LONG(rval);
		*(id *)ocval = (id)CFNumberCreate(NULL, kCFNumberLongType, &v);
	    }
	    else {
#if HAVE_LONG_LONG
		long long v = NUM2LL(rval);
		*(id *)ocval = 
		    (id)CFNumberCreate(NULL, kCFNumberLongLongType, &v);
#else
		long v = NUM2LONG(rval);
		*(id *)ocval = (id)CFNumberCreate(NULL, kCFNumberLongType, &v);
#endif
	    }
	    CFMakeCollectable(*(id *)ocval);
	    return true;
	}

	case T_SYMBOL:
	{
	    ID name = SYM2ID(rval);
	    *(id *)ocval = (id)CFStringCreateWithCString(NULL, rb_id2name(name),
		kCFStringEncodingASCII); /* XXX this is temporary */
	    CFMakeCollectable(*(id *)ocval);
	    return true;
	}
    }

    return false;
}

static bool
rb_objc_rval_to_ocsel(VALUE rval, void **ocval)
{
    const char *cstr;

    switch (TYPE(rval)) {
	case T_STRING:
	    cstr = StringValuePtr(rval);
	    break;

	case T_SYMBOL:
	    cstr = rb_id2name(SYM2ID(rval));
	    break;

	default:
	    return false;
    }

    *(SEL *)ocval = sel_registerName(cstr);
    return true;
}

static void *
bs_element_boxed_get_data(bs_element_boxed_t *bs_boxed, VALUE rval,
			  bool *success)
{
    void *data;

    assert(bs_boxed->ffi_type != NULL);

    if (NIL_P(rval) && bs_boxed->ffi_type == &ffi_type_pointer) {
	*success = true;
	return NULL;
    }

    if (rb_obj_is_kind_of(rval, rb_cBoxed) == Qfalse) {
	*success = false;
	return NULL;
    } 
    
    Data_Get_Struct(rval, void, data);

    if (bs_boxed->type == BS_ELEMENT_STRUCT) {
	bs_element_struct_t *bs_struct;
	unsigned i;

	bs_struct = (bs_element_struct_t *)bs_boxed->value;

	/* Resync the ivars if necessary.
	 * This is required as a field may nest another structure, which
	 * could have been modified as a copy in the Ruby world.
	 */
	for (i = 0; i < bs_struct->fields_count; i++) {
	    VALUE *v;
	    v = &((VALUE *)(data + bs_boxed->ffi_type->size))[i];
	    if (*v != 0) {
		char buf[512];
		snprintf(buf, sizeof buf, "%s=", bs_struct->fields[i].name);
		rb_funcall(rval, rb_intern(buf), 1, *v);
		*v = 0;
	    }
	}
    }

    *success = true;		

    return data;
}

static void
rb_bs_boxed_assert_ffitype_ok(bs_element_boxed_t *bs_boxed)
{
    if (bs_boxed->ffi_type == NULL && bs_boxed->type == BS_ELEMENT_STRUCT) {
	/* Make sure the ffi_type is set before use. */
	rb_objc_octype_to_ffitype(
	    ((bs_element_struct_t *)bs_boxed->value)->type);
    }
    assert(bs_boxed->ffi_type != NULL);
}

static VALUE
rb_bs_boxed_new_from_ocdata(bs_element_boxed_t *bs_boxed, void *ocval)
{
    void *data;
    size_t soffset;

    if (ocval == NULL)
	return Qnil;

    if (bs_boxed->type == BS_ELEMENT_OPAQUE && *(void **)ocval == NULL)
	return Qnil;

    rb_bs_boxed_assert_ffitype_ok(bs_boxed);

    soffset = 0;
    if (bs_boxed->type == BS_ELEMENT_STRUCT) {
	soffset = ((bs_element_struct_t *)bs_boxed->value)->fields_count 
		* sizeof(VALUE);
    }

    data = xmalloc(soffset + bs_boxed->ffi_type->size);
    memcpy(data, ocval, bs_boxed->ffi_type->size);
    memset(data + bs_boxed->ffi_type->size, 0, soffset);

    return Data_Wrap_Struct(bs_boxed->klass, NULL, NULL, data);     
}

static long
rebuild_new_struct_ary(ffi_type **elements, VALUE orig, VALUE new)
{
    long n = 0;
    while ((*elements) != NULL) {
	if ((*elements)->type == FFI_TYPE_STRUCT) {
	    long i, n2;
	    VALUE tmp;

	    n2 = rebuild_new_struct_ary((*elements)->elements, orig, new);
	    tmp = rb_ary_new();
	    for (i = 0; i < n2; i++) {
		if (RARRAY_LEN(orig) == 0)
		    return 0;
		rb_ary_push(tmp, rb_ary_shift(orig));
	    }
	    rb_ary_push(new, tmp);
	}
	elements++;
	n++;
    } 
    return n;
}

static void rb_objc_rval_to_ocval(VALUE, const char *, void **);

static void *
rb_objc_rval_to_boxed_data(VALUE rval, bs_element_boxed_t *bs_boxed, bool *ok)
{
    void *data;

    if (TYPE(rval) == T_ARRAY && bs_boxed->type == BS_ELEMENT_STRUCT) {
	bs_element_struct_t *bs_struct;
	long i, n;
	size_t pos;

	bs_struct = (bs_element_struct_t *)bs_boxed->value;

	rb_bs_boxed_assert_ffitype_ok(bs_boxed);

	n = RARRAY_LEN(rval);
	if (n < bs_struct->fields_count)
	    rb_raise(rb_eArgError, 
		    "not enough elements in array `%s' to create " \
		    "structure `%s' (%ld for %d)", 
		    RSTRING_CPTR(rb_inspect(rval)), bs_struct->name, n, 
		    bs_struct->fields_count);

	if (n > bs_struct->fields_count) {
	    VALUE new_rval = rb_ary_new();
	    VALUE orig = rval;
	    rval = rb_ary_dup(rval);
	    rebuild_new_struct_ary(bs_boxed->ffi_type->elements, rval, 
		    new_rval);
	    n = RARRAY_LEN(new_rval);
	    if (RARRAY_LEN(rval) != 0 || n != bs_struct->fields_count) {
		rb_raise(rb_eArgError, 
			"too much elements in array `%s' to create " \
			"structure `%s' (%ld for %d)", 
			RSTRING_CPTR(rb_inspect(orig)), 
			bs_struct->name, RARRAY_LEN(orig), 
			bs_struct->fields_count);
	    }
	    rval = new_rval;
	}

	pos = bs_struct->fields_count * sizeof(VALUE);
	data = xmalloc(bs_boxed->ffi_type->size + pos);
	memset(data + bs_boxed->ffi_type->size, 0, pos);
	pos = 0;

	for (i = 0; i < bs_struct->fields_count; i++) {
	    VALUE o = RARRAY_AT(rval, i);
	    char *field_type = bs_struct->fields[i].type;
	    rb_objc_rval_to_ocval(o, field_type, data + pos);
	    pos += rb_objc_octype_to_ffitype(field_type)->size;
	}

	*ok = true;
    }
    else {
	data = bs_element_boxed_get_data(bs_boxed, rval, ok);
    }

    return data;
}

static void
rb_objc_rval_to_ocval(VALUE rval, const char *octype, void **ocval)
{
    bs_element_boxed_t *bs_boxed;
    bool ok = true;

    octype = rb_objc_skip_octype_modifiers(octype);

    if (*octype == _C_VOID)
	return;

    if (st_lookup(bs_boxeds, (st_data_t)octype, (st_data_t *)&bs_boxed)) {
	void *data;

	data = rb_objc_rval_to_boxed_data(rval, bs_boxed, &ok);
	if (ok) {
	    if (data == NULL)
		*(void **)ocval = NULL;
	    else {
		memcpy(ocval, data, bs_boxed->ffi_type->size);
		xfree(data);
	    }
	}
	goto bails; 
    }

    if (st_lookup(bs_cftypes, (st_data_t)octype, NULL))
	octype = "@";

    if (*octype != _C_BOOL) {
	if (rval == Qtrue)
	    rval = INT2FIX(1);
	else if (rval == Qfalse)
	    rval = INT2FIX(0);
    }

    switch (*octype) {
	case _C_ID:
	case _C_CLASS:
	    ok = rb_objc_rval_to_ocid(rval, ocval, false);
	    break;

	case _C_SEL:
	    ok = rb_objc_rval_to_ocsel(rval, ocval);
	    break;

	case _C_PTR:
	    if (NIL_P(rval)) {
		*(void **)ocval = NULL;
	    }
	    else if (TYPE(rval) == T_STRING) {
		*(char **)ocval = StringValuePtr(rval);
	    }	
	    else if (st_lookup(bs_boxeds, (st_data_t)octype + 1, 
		     (st_data_t *)&bs_boxed)) {
		void *data;

		data = rb_objc_rval_to_boxed_data(rval, bs_boxed, &ok);
		if (ok)
		    *(void **)ocval = data;
	    }
	    else {
		ok = false;
	    }
	    break;

	case _C_UCHR:
 	    *(unsigned char *)ocval = (unsigned char) 
		NUM2UINT(rb_Integer(rval));
	    break;

	case _C_BOOL:
	    {
		unsigned char v;

		switch (TYPE(rval)) {
		    case T_FALSE:
		    case T_NIL:
			v = 0;
			break;
		    case T_TRUE:
			/* All other types should be converted as true, to 
			 * follow the Ruby semantics (where for example any 
			 * integer is always true, even 0)
			 */
		    default:
			v = 1;
			break;
		}
		*(unsigned char *)ocval = v;
	    }
	    break;

	case _C_CHR:
	    if (TYPE(rval) == T_STRING && RSTRING_CLEN(rval) == 1) {
		*(char *)ocval = RSTRING_CPTR(rval)[0];
	    }
	    else {
		*(char *)ocval = (char) NUM2INT(rb_Integer(rval));
	    }
	    break;

	case _C_SHT:
	    *(short *)ocval = (short) NUM2INT(rb_Integer(rval));
	    break;

	case _C_USHT:
	    *(unsigned short *)ocval = 
		(unsigned short)NUM2UINT(rb_Integer(rval));
	    break;

	case _C_INT:
	    *(int *)ocval = (int) NUM2INT(rb_Integer(rval));
	    break;

	case _C_UINT:
	    *(unsigned int *)ocval = (unsigned int) NUM2UINT(rb_Integer(rval));
	    break;

	case _C_LNG:
	    *(long *)ocval = (long) NUM2LONG(rb_Integer(rval));
	    break;

	case _C_ULNG:
	    *(unsigned long *)ocval = (unsigned long)
		NUM2ULONG(rb_Integer(rval));
	    break;

#if HAVE_LONG_LONG
	case _C_LNG_LNG:
	    *(long long *)ocval = (long long) NUM2LL(rb_Integer(rval));
	    break;

	case _C_ULNG_LNG:
	    *(unsigned long long *)ocval = 
		(unsigned long long) NUM2ULL(rb_Integer(rval));
	    break;
#endif

	case _C_FLT:
	    *(float *)ocval = (float) RFLOAT_VALUE(rb_Float(rval));
	    break;

	case _C_DBL:
	    *(double *)ocval = RFLOAT_VALUE(rb_Float(rval));
	    break;

	case _C_CHARPTR:
	    {
		VALUE str = rb_obj_as_string(rval);
		*(char **)ocval = StringValuePtr(str);
	    }
	    break;

	default:
	    ok = false;
    }

bails:
    if (!ok)
    	rb_raise(rb_eArgError, "can't convert Ruby object `%s' to " \
		 "Objective-C value of type `%s'", 
		 RSTRING_CPTR(rb_inspect(rval)), octype);
}

VALUE
rb_objc_boot_ocid(id ocid)
{
    if (rb_objc_is_non_native((VALUE)ocid)) {
        /* Make sure the ObjC class is imported in Ruby. */ 
        rb_objc_import_class(object_getClass(ocid)); 
    }
    else if (RBASIC(ocid)->klass == 0) {
	/* This pure-Ruby object was created from Objective-C, we need to 
	 * initialize the Ruby bits. 
	 */
	VALUE klass;
        
	klass = rb_objc_import_class(object_getClass(ocid)); 

	RBASIC(ocid)->klass = klass;
	RBASIC(ocid)->flags = 
	    klass == rb_cString
	    ? T_STRING
	    : klass == rb_cArray
	    ? T_ARRAY
	    : klass == rb_cHash
	    ? T_HASH
	    : T_OBJECT;
    }

    return (VALUE)ocid;
}

static void
rb_objc_ocval_to_rbval(void **ocval, const char *octype, VALUE *rbval);

bool 
rb_objc_ocid_to_rval(void **ocval, VALUE *rbval)
{
    id ocid = *(id *)ocval;

    if (ocid == NULL) {
	*rbval = Qnil;
    }
    else {
	*rbval = rb_objc_boot_ocid(ocid);
    }

    return true;
}

static void
rb_objc_ocval_to_rbval(void **ocval, const char *octype, VALUE *rbval)
{
    bool ok;

    octype = rb_objc_skip_octype_modifiers(octype);
    ok = true;
    
    {
	bs_element_boxed_t *bs_boxed;

	if (st_lookup(bs_boxeds, (st_data_t)octype, 
		      (st_data_t *)&bs_boxed)) {
	    *rbval = rb_bs_boxed_new_from_ocdata(bs_boxed, ocval);
	    goto bails; 
	}

	if (st_lookup(bs_cftypes, (st_data_t)octype, NULL))
	    octype = "@";
    }
    
    switch (*octype) {
	case _C_ID:
	    ok = rb_objc_ocid_to_rval(ocval, rbval);
	    break;
	
	case _C_CLASS:
	    *rbval = rb_objc_import_class(*(Class *)ocval);
	    break;

	case _C_BOOL:
	    *rbval = *(bool *)ocval ? Qtrue : Qfalse;
	    break;

	case _C_CHR:
	    *rbval = INT2NUM(*(char *)ocval);
	    break;

	case _C_UCHR:
	    *rbval = UINT2NUM(*(unsigned char *)ocval);
	    break;

	case _C_SHT:
	    *rbval = INT2NUM(*(short *)ocval);
	    break;

	case _C_USHT:
	    *rbval = UINT2NUM(*(unsigned short *)ocval);
	    break;
	
	case _C_INT:
	    *rbval = INT2NUM(*(int *)ocval);
	    break;
	
	case _C_UINT:
	    *rbval = UINT2NUM(*(unsigned int *)ocval);
	    break;
	
	case _C_LNG:
	    *rbval = INT2NUM(*(long *)ocval);
	    break;
	
	case _C_ULNG:
	    *rbval = UINT2NUM(*(unsigned long *)ocval);
	    break;

	case _C_FLT:
	    *rbval = rb_float_new((double)(*(float *)ocval));
	    break;

	case _C_DBL:
	    *rbval = rb_float_new(*(double *)ocval);
	    break;

	case _C_SEL:
	    {
		const char *selname = sel_getName(*(SEL *)ocval);
		*rbval = rb_str_new2(selname);
	    }
	    break;

	case _C_CHARPTR:
	    *rbval =  *(void **)ocval == NULL
		? Qnil
		: rb_str_new2(*(char **)ocval);
	    break;

	case _C_PTR:
	    if (*(void **)ocval == NULL) {
		*rbval = Qnil;
	    }
	    else {
		/* TODO: wrap C pointers into a specific object */
		ok = false;
	    }
	    break;

	default:
	    ok = false;
    }

bails:
    if (!ok)
	rb_raise(rb_eArgError, "can't convert C/Objective-C value `%p' " \
		 "of type `%s' to Ruby object", ocval, octype);
}

static void
rb_objc_exc_raise(id exception)
{
    const char *name;
    const char *desc;

    name = [[exception name] UTF8String];
    desc = [[exception reason] UTF8String];

    rb_raise(rb_eRuntimeError, "%s: %s", name, desc);
}

static bs_element_method_t *
rb_bs_find_method(Class klass, SEL sel)
{
    do {
	bs_element_indexed_class_t *bs_class;
	bs_element_method_t *bs_method;

	if (st_lookup(bs_classes, (st_data_t)class_getName(klass),
	              (st_data_t *)&bs_class)) {
 	    struct st_table *t = class_isMetaClass(klass) 
		? bs_class->cmethods : bs_class->imethods;
	    if (t != NULL 
		&& st_lookup(t, (st_data_t)sel, (st_data_t *)&bs_method))
		return bs_method;
	}

	klass = class_getSuperclass(klass);
    }
    while (klass != NULL);

    return NULL;
}

static const char *
rb_objc_method_get_type(Method method, unsigned count, 
			bs_element_method_t *bs_method, int n,
			char *type, size_t type_len)
{
    if (bs_method != NULL) {
	unsigned i;
	if (n == -1 && bs_method->retval != NULL)
	    return bs_method->retval->type;	    
	for (i = 0; i < bs_method->args_count; i++) {
	    if (bs_method->args[i].index == i
		&& bs_method->args[i].type != NULL)
		return bs_method->args[i].type; 
	}
    }
    if (n == -1) {
	method_getReturnType(method, type, type_len);
    }
    else {
	if (n + 2 < count) {
	    method_getArgumentType(method, n + 2, type, type_len);
	}
	else {
	    assert(bs_method->variadic);
	    return "@"; /* FIXME: should parse the format string if any */
	}
    }
    return type;
}

extern NODE *rb_current_cfunc_node;

struct objc_ruby_closure_context {
    SEL selector;
    bs_element_method_t *bs_method;
    Method method;
    ffi_cif *cif;
    IMP imp;
    Class klass;
};

static VALUE
rb_objc_call_objc(int argc, VALUE *argv, id ocrcv, Class klass, 
		  bool super_call, struct objc_ruby_closure_context *ctx)
{
    unsigned i, real_count, count;
    ffi_type *ffi_rettype, **ffi_argtypes;
    void *ffi_ret, **ffi_args;
    ffi_cif *cif;
    const char *type;
    char buf[128];
    void *imp;

    count = method_getNumberOfArguments(ctx->method);
    assert(count >= 2);

    real_count = count;
    if (ctx->bs_method != NULL && ctx->bs_method->variadic) {
	if (argc < count - 2)
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		argc, count - 2);
	count = argc + 2;
    }
    else if (argc != count - 2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		 argc, count - 2);
    }

    if (count == 2) {
	method_getReturnType(ctx->method, buf, sizeof buf);
	if (buf[0] == '@' || buf[0] == 'v') {
	    /* Easy case! */
	    @try {
		if (super_call) {
		    struct objc_super s;
		    s.receiver = ocrcv;
		    s.class = klass;
		    ffi_ret = objc_msgSendSuper(&s, ctx->selector);
		}
		else {
		    ffi_ret = objc_msgSend(ocrcv, ctx->selector);
		}
	    }
	    @catch (id e) {
		rb_objc_exc_raise(e);
	    }
	    return buf[0] == '@' ? (VALUE)ffi_ret : Qnil;
	}
    } 

    if (ctx->cif == NULL) {
	const size_t s = sizeof(ffi_type *) * (count + 1);
	ffi_argtypes = ctx->bs_method != NULL && ctx->bs_method->variadic
	    ? (ffi_type **)alloca(s) : (ffi_type **)malloc(s);
	ffi_argtypes[0] = &ffi_type_pointer;
	ffi_argtypes[1] = &ffi_type_pointer;
    }

    ffi_args = (void **)alloca(sizeof(void *) * (count + 1));
    ffi_args[0] = &ocrcv;
    ffi_args[1] = &ctx->selector;

    if (super_call) {
	Method smethod;
	smethod = class_getInstanceMethod(klass, ctx->selector);
	assert(smethod != ctx->method);
	imp = method_getImplementation(smethod);
	assert(imp != NULL);
    }
    else {
	if (ctx->imp != NULL && ctx->klass == klass) {
	    imp = ctx->imp;
	}
	else {
	    ctx->imp = imp = ctx->method == 
		class_getInstanceMethod(klass, ctx->selector)
		    ? method_getImplementation(ctx->method)
		    : objc_msgSend; /* alea jacta est */
	}
    }

    for (i = 0; i < argc; i++) {
	ffi_type *ffi_argtype;

	type = rb_objc_method_get_type(ctx->method, real_count, ctx->bs_method, 
	    i, buf, sizeof buf);

	if (ctx->cif == NULL) {
	    ffi_argtypes[i + 2] = rb_objc_octype_to_ffitype(type);
	    assert(ffi_argtypes[i + 2]->size > 0);
	    ffi_argtype = ffi_argtypes[i + 2];
	}
	else {
	    ffi_argtype = ctx->cif->arg_types[i + 2];
	}

	ffi_args[i + 2] = (void *)alloca(ffi_argtype->size);
	rb_objc_rval_to_ocval(argv[i], type, ffi_args[i + 2]);
    }

    if (ctx->cif == NULL)
	ffi_argtypes[count] = NULL;
    ffi_args[count] = NULL;

    type = rb_objc_method_get_type(ctx->method, real_count, ctx->bs_method, 
	-1, buf, sizeof buf);
    ffi_rettype = ctx->cif == NULL 
	? rb_objc_octype_to_ffitype(type) : ctx->cif->rtype;

    cif = ctx->cif;
    if (cif == NULL) {
	if (ctx->bs_method != NULL && ctx->bs_method->variadic)
	    cif = (ffi_cif *)alloca(sizeof(ffi_cif));
	else
	    cif = ctx->cif = (ffi_cif *)malloc(sizeof(ffi_cif));
	if (ffi_prep_cif(cif, FFI_DEFAULT_ABI, count, ffi_rettype, 
			 ffi_argtypes) != FFI_OK) {
	    rb_fatal("can't prepare cif for objc method type `%s'",
		    method_getTypeEncoding(ctx->method));
	}
    }
    if (ffi_rettype != &ffi_type_void) {
	ffi_ret = (void *)alloca(ffi_rettype->size);
    }
    else {
	ffi_ret = NULL;
    }

    @try {
	ffi_call(cif, FFI_FN(imp), ffi_ret, ffi_args);
    }
    @catch (id e) {
	rb_objc_exc_raise(e);
    }

    if (ffi_rettype != &ffi_type_void) {
	VALUE resp;
	rb_objc_ocval_to_rbval(ffi_ret, type, &resp);
	return resp;
    }
    else {
	return Qnil;
    }
}

static VALUE
rb_objc_to_ruby_closure(int argc, VALUE *argv, VALUE rcv)
{
    id ocrcv;
    bool super_call;
    Class klass;
    struct objc_ruby_closure_context *ctx;

    rb_objc_rval_to_ocid(rcv, (void **)&ocrcv, true);
    super_call = (ruby_current_thread->cfp->flag >> FRAME_MAGIC_MASK_BITS) 
	& VM_CALL_SUPER_BIT;
    klass = super_call ? class_getSuperclass(*(Class *)ocrcv) : *(Class *)ocrcv;
    
    assert(rb_current_cfunc_node != NULL);

    if (rb_current_cfunc_node->u3.value == 0) {
	const char *selname;
	size_t selnamelen;

	ctx = (struct objc_ruby_closure_context *)xmalloc(sizeof(
	    struct objc_ruby_closure_context));

	selname = rb_id2name(rb_frame_this_func());
	selnamelen = strlen(selname);
	if (argc == 1 && selname[selnamelen - 1] != ':') {
	    char *tmp = alloca(selnamelen + 2);
	    snprintf(tmp, selnamelen + 2, "%s:", selname);
	    selname = (const char *)tmp;
	}
	ctx->selector = sel_registerName(selname);

	ctx->bs_method = rb_bs_find_method(*(Class *)rcv, ctx->selector);
	ctx->method = class_getInstanceMethod(*(Class *)rcv, ctx->selector); 
	assert(ctx->method != NULL);
	ctx->cif = NULL;
	ctx->imp = NULL;
	ctx->klass = NULL;
	GC_WB(&rb_current_cfunc_node->u3.value, ctx);
    }
    else {
	ctx = (struct objc_ruby_closure_context *)
	    rb_current_cfunc_node->u3.value;
    }

//NSLog(@"Ruby -> ObjC [%@ klass=%@ sel=%s argc=%d super_call=%d", ocrcv, (id)klass, (char *)ctx->selector, argc, super_call);

    return rb_objc_call_objc(argc, argv, ocrcv, klass, super_call, ctx);
}

static VALUE
rb_super_objc_send(int argc, VALUE *argv, VALUE rcv)
{
    struct objc_ruby_closure_context fake_ctx;
    id ocrcv;
    ID mid;
    Class klass;

    if (argc < 1)
	rb_raise(rb_eArgError, "expected at least one argument");

    mid = rb_to_id(argv[0]);
    argv++;
    argc--;

    rb_objc_rval_to_ocid(rcv, (void **)&ocrcv, true);
    klass = class_getSuperclass(*(Class *)ocrcv);

    fake_ctx.selector = sel_registerName(rb_id2name(mid));
    fake_ctx.method = class_getInstanceMethod(klass, fake_ctx.selector); 
    assert(fake_ctx.method != NULL);
    fake_ctx.bs_method = NULL;
    fake_ctx.cif = NULL;
    fake_ctx.imp = NULL;
    fake_ctx.klass = NULL;

    return rb_objc_call_objc(argc, argv, ocrcv, klass, true, &fake_ctx);
}

#define IGNORE_PRIVATE_OBJC_METHODS 1

static void
rb_ruby_to_objc_closure_handler(ffi_cif *cif, void *resp, void **args,
				void *userdata)
{
    void *rcv;
    SEL sel;
    ID mid;
    VALUE rrcv, ret;
    Method method;
    char type[128];
    long i, argc;
    VALUE *argv;
    NODE *body;

    rcv = (*(id **)args)[0];
    sel = (*(SEL **)args)[1];
    body = (NODE *)userdata;

    method = class_getInstanceMethod(*(Class *)rcv, sel);
    assert(method != NULL);

    argc = cif->nargs - 2;
    argv = (VALUE *)alloca(sizeof(VALUE) * argc);
    for (i = 0; i < argc; i++) {
	VALUE val;
        
	method_getArgumentType(method, i + 2, type, sizeof type);
	rb_objc_ocval_to_rbval(args[i + 2], type, &val);
        argv[i] = val;
    }

    rb_objc_ocid_to_rval(&rcv, &rrcv);

    mid = rb_intern((const char *)sel);

//NSLog(@"ObjC -> Ruby [%@ mid=%s]\n", rrcv, rb_id2name(mid));

    VALUE rb_vm_call(rb_thread_t * th, VALUE klass, VALUE recv, VALUE id, 
		     ID oid, int argc, const VALUE *argv, const NODE *body, 
		     int nosuper);

    ret = rb_vm_call(GET_THREAD(), CLASS_OF(rrcv), rrcv, mid, Qnil,
		     argc, argv, body, 0);

    method_getReturnType(method, type, sizeof type);
    rb_objc_rval_to_ocval(ret, type, resp);
}

static void *
rb_ruby_to_objc_closure(const char *octype, unsigned arity, NODE *node)
{
    const char *p;
    char buf[128];
    ffi_type *ret, **args;
    ffi_cif *cif;
    ffi_closure *closure;
    unsigned i;

    p = octype;

    assert((p = rb_objc_get_first_type(p, buf, sizeof buf)) != NULL);
    ret = rb_objc_octype_to_ffitype(buf);

    args = (ffi_type **)malloc(sizeof(ffi_type *) * (arity + 2)); 
    i = 0;
    while ((p = rb_objc_get_first_type(p, buf, sizeof buf)) != NULL) {
	args[i] = rb_objc_octype_to_ffitype(buf);
	assert(++i <= arity + 2);
    }

    cif = (ffi_cif *)malloc(sizeof(ffi_cif));
    if (ffi_prep_cif(cif, FFI_DEFAULT_ABI, arity + 2, ret, args) != FFI_OK)
	rb_fatal("can't prepare ruby to objc cif");
    
    closure = (ffi_closure *)malloc(sizeof(ffi_closure));
    if (ffi_prep_closure(closure, cif, rb_ruby_to_objc_closure_handler, node)
	!= FFI_OK)
	rb_fatal("can't prepare ruby to objc closure");

    return closure;
}

void
rb_objc_sync_ruby_method(VALUE mod, ID mid, NODE *node, unsigned override)
{
    SEL sel;
    Class ocklass;
    Method method;
    char *types;
    int arity;
    char *mid_str;
    IMP imp;
    bool direct_override;

    /* Do not expose C functions. */
    if (bs_functions != NULL
	&& mod == CLASS_OF(rb_mKernel)
	&& st_lookup(bs_functions, (st_data_t)mid, NULL))
	return;

    arity = rb_node_arity(node);
    mid_str = (char *)rb_id2name(mid);

    if (arity < 0) {
	//printf("mid %s has negative arity %d\n", mid_str, arity);
	return;
    }

    if (arity == 1 && mid_str[strlen(mid_str) - 1] != ':') {
	char buf[100];
	snprintf(buf, sizeof buf, "%s:", mid_str);
	sel = sel_registerName(buf);
    }
    else {
	sel = sel_registerName(mid_str);
    }

    ocklass = RCLASS_OCID(mod);
    direct_override = false;
    method = class_getInstanceMethod(ocklass, sel);

    if (method != NULL) {
	void *klass;
	if (!override)
	    return;

        /* Do not override certain NSObject selectors. */
        if (sel == @selector(superclass)
	    || sel == @selector(hash)
	    || sel == @selector(zone)) {
 	    klass = RCLASS_OCID(rb_cBasicObject);
	    if (class_getInstanceMethod(klass, sel) == method)
		return;
	}

	if (arity >= 0 && arity + 2 != method_getNumberOfArguments(method)) {
	    rb_warning("cannot override Objective-C method `%s' in " \
		       "class `%s' because of an arity mismatch (%d for %d)", 
		       (char *)sel, 
		       class_getName(ocklass), 
		       arity + 2, 
		       method_getNumberOfArguments(method));
	    return;
	}
	types = (char *)method_getTypeEncoding(method);
	klass = class_getSuperclass(ocklass);
	direct_override = 
	    klass == NULL || class_getInstanceMethod(klass, sel) != method;
    }
    else {
	struct st_table *t = class_isMetaClass(ocklass)
	    ? bs_inf_prot_cmethods
	    : bs_inf_prot_imethods;

	if (t == NULL || !st_lookup(t, (st_data_t)sel, (st_data_t *)&types)) {
	    types = (char *)alloca((arity + 4) * sizeof(char));
	    types[0] = '@';
	    types[1] = '@';
	    types[2] = ':';
	    memset(&types[3], '@', arity);
	    types[arity + 3] = '\0';
	}
    }

//    printf("registering sel %s of types %s arity %d to class %s\n",
//	   (char *)sel, types, arity, class_getName(ocklass));

    imp = rb_ruby_to_objc_closure(types, arity, node);

    if (method != NULL && direct_override) {
	method_setImplementation(method, imp);
    }
    else {
	assert(class_addMethod(ocklass, sel, imp, types));	
    }
}

static int
__rb_objc_add_ruby_method(ID mid, NODE *body, VALUE mod)
{
    if (mid == ID_ALLOCATOR)
	return ST_CONTINUE;
    
    if (body == NULL || body->nd_body->nd_body == NULL)
	return ST_CONTINUE;

    if ((body->nd_body->nd_noex & NOEX_MASK) != NOEX_PUBLIC)
	return ST_CONTINUE;

    rb_objc_sync_ruby_method(mod, mid, body->nd_body->nd_body, 0);

    return ST_CONTINUE;
}

void
rb_objc_sync_ruby_methods(VALUE mod, VALUE klass)
{
    for (;;) {
	st_foreach(RCLASS_M_TBL(mod), __rb_objc_add_ruby_method, 
		   (st_data_t)klass);
	mod = RCLASS_SUPER(mod);
	if (mod == 0 || BUILTIN_TYPE(mod) != T_ICLASS)
	    break;
    }
}

static inline unsigned
is_ignored_selector(SEL sel)
{
#if defined(__ppc__)
    return sel == (SEL)0xfffef000;
#elif defined(__i386__)
    return sel == (SEL)0xfffeb010;
#else
# error Unsupported arch
#endif
}

#if 0
static void
__rb_objc_sync_methods(VALUE mod, Class ocklass)
{
    Method *methods;
    unsigned int i, count;
    char buffer[128];
    VALUE imod;

    methods = class_copyMethodList(ocklass, &count);

    imod = mod;
#if 0
    for (;;) {
	st_foreach(RCLASS_M_TBL(imod), __rb_objc_add_ruby_method, 
		   (st_data_t)mod);
	imod = RCLASS_SUPER(imod);
	if (imod == 0 || BUILTIN_TYPE(imod) != T_ICLASS)
	    break;
    }
#endif

    for (i = 0; i < count; i++) {
	SEL sel;
	ID mid;
	st_data_t data;
	NODE *node;

	sel = method_getName(methods[i]);
	if (is_ignored_selector(sel))
	    continue;
#if IGNORE_PRIVATE_OBJC_METHODS
	if (*(char *)sel == '_')
	    continue;
#endif

	rb_objc_sel_to_mid(sel, buffer, sizeof buffer);
	mid = rb_intern(buffer);

	if (rb_method_boundp(mod, mid, 1) == Qtrue)
	    continue;

	node = NEW_CFUNC(rb_objc_to_ruby_closure(methods[i]), -2); 
	data = (st_data_t)NEW_FBODY(NEW_METHOD(node, mod, 
		    			       NOEX_WITH_SAFE(NOEX_PUBLIC)), 0);

	st_insert(RCLASS_M_TBL(mod), mid, data);
    }

    free(methods);
}
#endif

NODE *
rb_objc_define_objc_mid_closure(VALUE recv, ID mid, ID alias_mid)
{
    SEL sel;
    Class ocklass;
    Method method;
    VALUE mod;
    NODE *node, *data;
    Method (*getMethod)(Class, SEL);

    assert(mid > 1);

    sel = sel_registerName(rb_id2name(mid));

    if (!rb_special_const_p(recv) && !rb_objc_is_non_native(recv) 
	&& TYPE(recv) == T_CLASS) {
	mod = recv;
	getMethod = class_getClassMethod;
    }
    else {
	mod = CLASS_OF(recv);
	getMethod = class_getInstanceMethod;
    }

    ocklass = RCLASS_OCID(mod);

    if (class_isMetaClass(ocklass))
	return NULL;

    method = (*getMethod)(ocklass, sel);
    if (method == NULL || method_getImplementation(method) == NULL)
	return NULL;	/* recv doesn't respond to this selector */

    do {
	Class ocsuper = class_getSuperclass(ocklass);
	if ((*getMethod)(ocsuper, sel) == NULL) /* != method */
	    break;
	ocklass = ocsuper;
    }
    while (1);

    if (RCLASS(mod)->ocklass != ocklass) {
	mod = rb_objc_import_class(ocklass);
	if (TYPE(recv) == T_CLASS)
	    mod = CLASS_OF(mod);
    }

    /* Already defined. */
    node = rb_method_node(mod, mid);
    if (node != NULL)
	return node;

    node = NEW_CFUNC(rb_objc_to_ruby_closure, -1);
    data = NEW_FBODY(NEW_METHOD(node, mod, 
				NOEX_WITH_SAFE(NOEX_PUBLIC)), 0);

    rb_add_method_direct(mod, mid, data);

    if (alias_mid != 0)
	rb_add_method_direct(mod, alias_mid, data);

    return data->nd_body;
}

#if 0
rb_objc_sync_objc_methods_into(VALUE mod, Class ocklass)
{
    /* Load instance methods */
    __rb_objc_sync_methods(mod, ocklass);

    /* Load class methods */
    __rb_objc_sync_methods(rb_singleton_class(mod), 
			   object_getClass((id)ocklass));
}

void
rb_objc_sync_objc_methods(VALUE mod)
{
    rb_objc_sync_objc_methods_into(mod, RCLASS_OCID(mod));
}
#endif

VALUE
rb_mod_objc_ancestors(VALUE recv)
{
    void *klass;
    VALUE ary;

    ary = rb_ary_new();

    for (klass = RCLASS(recv)->ocklass; klass != NULL; 
	 klass = class_getSuperclass(klass)) {
	rb_ary_push(ary, rb_str_new2(class_getName(klass)));		
    }

    return ary;
}

void 
rb_objc_methods(VALUE ary, Class ocklass)
{
    while (ocklass != NULL) {
	unsigned i, count;
	Method *methods;

 	methods = class_copyMethodList(ocklass, &count);
 	if (methods != NULL) { 
	    for (i = 0; i < count; i++) {
		SEL sel = method_getName(methods[i]);
		if (is_ignored_selector(sel))
		    continue;
		rb_ary_push(ary, ID2SYM(rb_intern(sel_getName(sel))));
	    }
	    free(methods);
    	}
	ocklass = class_getSuperclass(ocklass);
    }

    rb_funcall(ary, rb_intern("uniq!"), 0);
}

static bool
rb_objc_resourceful(VALUE obj)
{
    /* TODO we should export this function in the runtime 
     * Object#__resourceful__? perhaps? 
     */
    extern CFTypeID __CFGenericTypeID(void *);
    CFTypeID t = __CFGenericTypeID((void *)obj);
    if (t > 0) {
	extern void *_CFRuntimeGetClassWithTypeID(CFTypeID);
	long *d = (long *)_CFRuntimeGetClassWithTypeID(t);
	/* first long is version, 4 means resourceful */
	if (d != NULL && *d & 4)
	    return true;	
    }
    return false;
}

static VALUE
bs_function_dispatch(int argc, VALUE *argv, VALUE recv)
{
    ID callee;
    bs_element_function_t *bs_func;
    void *sym;
    unsigned i;
    ffi_type *ffi_rettype, **ffi_argtypes;
    void *ffi_ret, **ffi_args;
    ffi_cif *cif;
    VALUE resp;

    callee = rb_frame_this_func();
    assert(callee > 1);
    if (!st_lookup(bs_functions, (st_data_t)callee, (st_data_t *)&bs_func))
	rb_bug("bridgesupport function `%s' not in cache", rb_id2name(callee));

    if (!st_lookup(bs_function_syms, (st_data_t)callee, (st_data_t *)&sym)
	|| sym == NULL) {
	sym = dlsym(RTLD_DEFAULT, bs_func->name);
	if (sym == NULL)
	    rb_bug("cannot locate symbol for bridgesupport function `%s'",
		   bs_func->name);
	st_insert(bs_function_syms, (st_data_t)callee, (st_data_t)sym);
    }

    if (argc != bs_func->args_count)
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		 argc, bs_func->args_count);

    ffi_argtypes = (ffi_type **)alloca(sizeof(ffi_type *) * argc + 1);
    ffi_args = (void **)alloca(sizeof(void *) * argc + 1);

    for (i = 0; i < argc; i++) {
	char *type = bs_func->args[i].type;
	ffi_argtypes[i] = rb_objc_octype_to_ffitype(type);
	ffi_args[i] = (void *)alloca(ffi_argtypes[i]->size);
	rb_objc_rval_to_ocval(argv[i], type, ffi_args[i]);
    }

    ffi_argtypes[argc] = NULL;
    ffi_args[argc] = NULL;

    ffi_rettype = bs_func->retval == NULL
    	? &ffi_type_void
	: rb_objc_octype_to_ffitype(bs_func->retval->type);

    cif = (ffi_cif *)alloca(sizeof(ffi_cif));
    if (ffi_prep_cif(cif, FFI_DEFAULT_ABI, argc, ffi_rettype, ffi_argtypes) 
	!= FFI_OK)
	rb_fatal("can't prepare cif for function `%s'", bs_func->name);

    if (ffi_rettype != &ffi_type_void) {
	ffi_ret = (void *)alloca(ffi_rettype->size);
    }
    else {
	ffi_ret = NULL;
    }

    @try {
	ffi_call(cif, FFI_FN(sym), ffi_ret, ffi_args);
    }
    @catch (id e) {
	rb_objc_exc_raise(e);
    }

    resp = Qnil;
    if (ffi_rettype != &ffi_type_void) {
	rb_objc_ocval_to_rbval(ffi_ret, bs_func->retval->type, &resp);
    	if (bs_func->retval->already_retained && !rb_objc_resourceful(resp))
	    CFMakeCollectable((void *)resp);
    }
    return resp;
}

VALUE
rb_objc_resolve_const_value(VALUE v, VALUE klass, ID id)
{
    void *sym;
    bs_element_constant_t *bs_const;

    if (v == rb_objc_class_magic_cookie) {
	v = rb_objc_import_class(objc_getClass(rb_id2name(id)));
    }
    else if (v == bs_const_magic_cookie) { 
	if (!st_lookup(bs_constants, (st_data_t)id, (st_data_t *)&bs_const))
	    rb_bug("unresolved bridgesupport constant `%s' not in cache",
		    rb_id2name(id));

	sym = dlsym(RTLD_DEFAULT, bs_const->name);
	if (sym == NULL)
	    rb_bug("cannot locate symbol for unresolved bridgesupport " \
		    "constant `%s'", bs_const->name);

	rb_objc_ocval_to_rbval(sym, bs_const->type, &v);
    
	/* To avoid a runtime warning when re-defining the constant, we remove
	 * its entry from the table before.
	 */
	klass = rb_cObject;
	assert(RCLASS_IV_TBL(klass) != NULL);
	assert(st_delete(RCLASS_IV_TBL(klass), (st_data_t*)&id, NULL));

	rb_const_set(klass, id, v); 
    }

    return v;
}

static bs_element_boxed_t *
rb_klass_get_bs_boxed(VALUE recv)
{
    bs_element_boxed_t *bs_boxed;
    VALUE type;

    type = rb_ivar_get(recv, rb_ivar_type);
    if (NIL_P(type))
	rb_bug("cannot get boxed objc type of class `%s'", 
	       rb_class2name(recv));
    
    assert(TYPE(type) == T_STRING);

    if (st_lookup(bs_boxeds, (st_data_t)StringValuePtr(type), 
		  (st_data_t *)&bs_boxed)) {
	rb_bs_boxed_assert_ffitype_ok(bs_boxed);
	return bs_boxed;
    }
    return NULL;
}

static VALUE
rb_bs_struct_new(int argc, VALUE *argv, VALUE recv)
{
    bs_element_boxed_t *bs_boxed = rb_klass_get_bs_boxed(recv);
    bs_element_struct_t *bs_struct = (bs_element_struct_t *)bs_boxed->value;    
    void *data;
    unsigned i;
    size_t pos;

    if (argc > 0 && argc != bs_struct->fields_count)
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		 argc, bs_struct->fields_count);

    pos = bs_struct->fields_count * sizeof(VALUE);
    data = (void *)xmalloc(pos + bs_boxed->ffi_type->size);
    memset(data, 0, pos + bs_boxed->ffi_type->size);
    pos = 0;

    for (i = 0; i < argc; i++) {
	bs_element_struct_field_t *bs_field = 
	    (bs_element_struct_field_t *)&bs_struct->fields[i];

	rb_objc_rval_to_ocval(argv[i], bs_field->type, data + pos);
    
        pos += rb_objc_octype_to_ffitype(bs_field->type)->size;
    }

    return Data_Wrap_Struct(recv, NULL, NULL, data);
}

static ID
rb_bs_struct_field_ivar_id(void)
{
    char ivar_name[128];
    int len;

    len = snprintf(ivar_name, sizeof ivar_name, "@%s", 
		   rb_id2name(rb_frame_this_func()));
    if (ivar_name[len - 1] == '=')
	ivar_name[len - 1] = '\0';

    return rb_intern(ivar_name);
}

static VALUE
rb_bs_struct_get(VALUE recv)
{
    bs_element_boxed_t *bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(recv));
    bs_element_struct_t *bs_struct = (bs_element_struct_t *)bs_boxed->value;
    unsigned i;
    const char *ivar_id_str;
    void *data;
    size_t pos;

    /* FIXME we should cache the ivar IDs somewhere in the 
     * bs_element_struct_fields 
     */

    ivar_id_str = rb_id2name(rb_bs_struct_field_ivar_id());
    ivar_id_str++; /* skip first '@' */

    Data_Get_Struct(recv, void, data);
    assert(data != NULL);

    rb_objc_wb_range(data + bs_boxed->ffi_type->size,
		     bs_struct->fields_count * sizeof(VALUE));

    for (i = 0, pos = 0; i < bs_struct->fields_count; i++) {
	bs_element_struct_field_t *bs_field =
	    (bs_element_struct_field_t *)&bs_struct->fields[i];

	if (strcmp(ivar_id_str, bs_field->name) == 0) {
	    VALUE *val;

	    val = &((VALUE *)(data + bs_boxed->ffi_type->size))[i];
	    if (*val == 0)
		rb_objc_ocval_to_rbval(data + pos, bs_field->type, val);
	    return *val;
	}
        pos += rb_objc_octype_to_ffitype(bs_field->type)->size;
    }

    rb_bug("can't find field `%s' in recv `%s'", ivar_id_str,
	   RSTRING_CPTR(rb_inspect(recv)));

    return Qnil;
}

static VALUE
rb_bs_struct_set(VALUE recv, VALUE value)
{
    bs_element_boxed_t *bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(recv));
    bs_element_struct_t *bs_struct = (bs_element_struct_t *)bs_boxed->value;
    unsigned i;
    const char *ivar_id_str;
    void *data;
    size_t pos;

    /* FIXME we should cache the ivar IDs somewhere in the 
     * bs_element_struct_fields 
     */

    ivar_id_str = rb_id2name(rb_bs_struct_field_ivar_id());
    ivar_id_str++; /* skip first '@' */

    Data_Get_Struct(recv, void, data);
    assert(data != NULL);

    for (i = 0, pos = 0; i < bs_struct->fields_count; i++) {
	bs_element_struct_field_t *bs_field =
	    (bs_element_struct_field_t *)&bs_struct->fields[i];

	if (strcmp(ivar_id_str, bs_field->name) == 0) {
	    rb_objc_rval_to_ocval(value, bs_field->type, data + pos);
	    /* We do not update the cache because `value' may have been
	     * transformed (ex. fixnum to float).
	     */
	    ((VALUE *)(data + bs_boxed->ffi_type->size))[i] = 0;
	    return value;
	}
        pos += rb_objc_octype_to_ffitype(bs_field->type)->size;
    }

    rb_bug("can't find field `%s' in recv `%s'", ivar_id_str,
	   RSTRING_CPTR(rb_inspect(recv)));

    return Qnil;
}

static VALUE
rb_bs_struct_to_a(VALUE recv)
{
    bs_element_boxed_t *bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(recv));
    bs_element_struct_t *bs_struct = (bs_element_struct_t *)bs_boxed->value;    
    VALUE ary;
    unsigned i;

    ary = rb_ary_new();

    for (i = 0; i < bs_struct->fields_count; i++) {
	VALUE obj;

	obj = rb_funcall(recv, rb_intern(bs_struct->fields[i].name), 0, NULL);
	rb_ary_push(ary, obj);
    }

    return ary;
}

static VALUE
rb_bs_boxed_is_equal(VALUE recv, VALUE other)
{
    bs_element_boxed_t *bs_boxed;  
    bool ok;
    void *d1, *d2; 

    if (recv == other)
	return Qtrue;

    if (rb_obj_is_kind_of(other, rb_cBoxed) == Qfalse)
	return Qfalse;

    bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(recv));
    if (bs_boxed != rb_klass_get_bs_boxed(CLASS_OF(other)))
	return Qfalse;

    d1 = bs_element_boxed_get_data(bs_boxed, recv, &ok);
    if (!ok)
	rb_raise(rb_eRuntimeError, "can't retrieve data for boxed `%s'",
		 RSTRING_CPTR(rb_inspect(recv)));

    d2 = bs_element_boxed_get_data(bs_boxed, other, &ok);
    if (!ok)
	rb_raise(rb_eRuntimeError, "can't retrieve data for boxed `%s'",
		 RSTRING_CPTR(rb_inspect(recv)));

    if (d1 == d2)
	return Qtrue;
    else if (d1 == NULL || d2 == NULL)
	return Qfalse;

    return memcmp(d1, d2, bs_boxed->ffi_type->size) == 0 ? Qtrue : Qfalse;
}

static VALUE
rb_bs_struct_dup(VALUE recv)
{
    bs_element_boxed_t *bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(recv));
    void *data;
    bool ok;

    data = bs_element_boxed_get_data(bs_boxed, recv, &ok);
    if (!ok)
	rb_raise(rb_eRuntimeError, "can't retrieve data for boxed `%s'",
		 RSTRING_CPTR(rb_inspect(recv)));

    if (data == NULL)
	return Qnil;

    return rb_bs_boxed_new_from_ocdata(bs_boxed, data);
}

static VALUE
rb_bs_struct_inspect(VALUE recv)
{
    bs_element_boxed_t *bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(recv));
    bs_element_struct_t *bs_struct = (bs_element_struct_t *)bs_boxed->value;    
    unsigned i;
    VALUE str;

    str = rb_str_new2("#<");
    rb_str_cat2(str, rb_obj_classname(recv));

    if (!bs_struct->opaque) {
	for (i = 0; i < bs_struct->fields_count; i++) {
	    VALUE obj;

	    obj = rb_funcall(recv, rb_intern(bs_struct->fields[i].name), 
			     0, NULL);
	    rb_str_cat2(str, " ");
	    rb_str_cat2(str, bs_struct->fields[i].name);
	    rb_str_cat2(str, "=");
	    rb_str_append(str, rb_inspect(obj));
	}
    }

    rb_str_cat2(str, ">");

    return str;
}

static VALUE
rb_boxed_objc_type(VALUE recv)
{
    char *type;

    bs_element_boxed_t *bs_boxed;

    bs_boxed = rb_klass_get_bs_boxed(recv);
    type = bs_boxed->type == BS_ELEMENT_OPAQUE
	? ((bs_element_opaque_t *)bs_boxed->value)->type
	: ((bs_element_struct_t *)bs_boxed->value)->type;

    return rb_str_new2(type);
}

static VALUE
rb_boxed_is_opaque(VALUE recv)
{
    bs_element_boxed_t *bs_boxed;

    bs_boxed = rb_klass_get_bs_boxed(recv);
    if (bs_boxed->type == BS_ELEMENT_OPAQUE)
	return Qtrue;

    return ((bs_element_struct_t *)bs_boxed->value)->opaque ? Qtrue : Qfalse;
}

static VALUE
rb_boxed_fields(VALUE recv)
{
    bs_element_boxed_t *bs_boxed;
    VALUE ary;
    unsigned i;

    bs_boxed = rb_klass_get_bs_boxed(recv);

    ary = rb_ary_new();
    if (bs_boxed->type == BS_ELEMENT_STRUCT) {
	bs_element_struct_t *bs_struct;
	bs_struct = (bs_element_struct_t *)bs_boxed->value;
	for (i = 0; i < bs_struct->fields_count; i++)
	    rb_ary_push(ary, ID2SYM(rb_intern(bs_struct->fields[i].name)));
    }
    return ary;
}

static void
setup_bs_boxed_type(bs_element_type_t type, void *value)
{
    bs_element_boxed_t *bs_boxed;
    VALUE klass;
    struct __bs_boxed {
	char *name;
	char *type;
    } *p;
    ffi_type *bs_ffi_type;

    p = (struct __bs_boxed *)value;

    klass = rb_define_class(p->name, rb_cBoxed);
    assert(!NIL_P(klass));
    rb_ivar_set(klass, rb_ivar_type, rb_str_new2(p->type));

    if (type == BS_ELEMENT_STRUCT) {
	bs_element_struct_t *bs_struct = (bs_element_struct_t *)value;
	char buf[128];
	int i;

	/* Needs to be lazily created, because the type of some fields
	 * may not be registered yet.
	 */
        bs_ffi_type = NULL; 

	if (!bs_struct->opaque) {
	    for (i = 0; i < bs_struct->fields_count; i++) {
		bs_element_struct_field_t *field = &bs_struct->fields[i];
		rb_define_method(klass, field->name, rb_bs_struct_get, 0);
		strlcpy(buf, field->name, sizeof buf);
		strlcat(buf, "=", sizeof buf);
		rb_define_method(klass, buf, rb_bs_struct_set, 1);
	    }
	    rb_define_method(klass, "to_a", rb_bs_struct_to_a, 0);
	}

	rb_define_singleton_method(klass, "new", rb_bs_struct_new, -1);
	rb_define_method(klass, "dup", rb_bs_struct_dup, 0);
	rb_define_alias(klass, "clone", "dup");	
	rb_define_method(klass, "inspect", rb_bs_struct_inspect, 0);
    }
    else {
	rb_undef_alloc_func(klass);
	rb_undef_method(CLASS_OF(klass), "new");
	bs_ffi_type = &ffi_type_pointer;
    }
    rb_define_method(klass, "==", rb_bs_boxed_is_equal, 1);

    bs_boxed = (bs_element_boxed_t *)malloc(sizeof(bs_element_boxed_t));
    bs_boxed->type = type;
    bs_boxed->value = value; 
    bs_boxed->klass = klass;
    bs_boxed->ffi_type = bs_ffi_type;

    st_insert(bs_boxeds, (st_data_t)p->type, (st_data_t)bs_boxed);
}

static inline ID
generate_const_name(char *name)
{
    ID id;
    if (islower(name[0])) {
	name[0] = toupper(name[0]);
	id = rb_intern(name);
	name[0] = tolower(name[0]);
	return id;
    }
    else {
	return rb_intern(name);
    }
}

static void
bs_parse_cb(const char *path, bs_element_type_t type, void *value, void *ctx)
{
    bool do_not_free = false;
    switch (type) {
	case BS_ELEMENT_ENUM:
	{
	    bs_element_enum_t *bs_enum = (bs_element_enum_t *)value;
	    ID name = generate_const_name(bs_enum->name);
	    if (!rb_const_defined(rb_cObject, name)) {
		VALUE val = strchr(bs_enum->value, '.') != NULL
		    ? rb_float_new(rb_cstr_to_dbl(bs_enum->value, 1))
		    : rb_cstr_to_inum(bs_enum->value, 10, 1);
		rb_const_set(rb_cObject, name, val); 
	    }
	    else {
		rb_warning("bs: enum `%s' already defined", rb_id2name(name));
	    }
	    break;
	}

	case BS_ELEMENT_CONSTANT:
	{
	    bs_element_constant_t *bs_const = (bs_element_constant_t *)value;
	    ID name = generate_const_name(bs_const->name);
	    if (!rb_const_defined(rb_cObject, name)) {	
		st_insert(bs_constants, (st_data_t)name, (st_data_t)bs_const);
		rb_const_set(rb_cObject, name, bs_const_magic_cookie); 
		do_not_free = true;
	    }
	    else {
		rb_warning("bs: constant `%s' already defined", 
			   rb_id2name(name));
	    }
	    break;
	}

	case BS_ELEMENT_STRING_CONSTANT:
	{
	    bs_element_string_constant_t *bs_strconst = 
		(bs_element_string_constant_t *)value;
	    ID name = generate_const_name(bs_strconst->name);
	    if (!rb_const_defined(rb_cObject, name)) {	
		VALUE val;
	    	if (bs_strconst->nsstring) {
		    CFStringRef string;
		    string = CFStringCreateWithCString(
			NULL, bs_strconst->value, kCFStringEncodingUTF8);
		    val = (VALUE)string;
	    	}
	    	else {
		    val = rb_str_new2(bs_strconst->value);
	    	}
		rb_const_set(rb_cObject, name, val);
	    }
	    else {
		rb_warning("bs: string constant `%s' already defined", 
			   rb_id2name(name));
	    }
	    break;
	}

	case BS_ELEMENT_FUNCTION:
	{
	    bs_element_function_t *bs_func = (bs_element_function_t *)value;
	    ID name = rb_intern(bs_func->name);
	    if (1) {
		st_insert(bs_functions, (st_data_t)name, (st_data_t)bs_func);
		/* FIXME we should reuse the same node for all functions */
		rb_define_global_function(
		    bs_func->name, bs_function_dispatch, -1);
		do_not_free = true;
	    }
	    else {
		rb_warning("bs: function `%s' already defined", bs_func->name);
	    }
	    break;
	}

	case BS_ELEMENT_FUNCTION_ALIAS:
	{
	    bs_element_function_alias_t *bs_func_alias = 
		(bs_element_function_alias_t *)value;
	    rb_define_alias(CLASS_OF(rb_mKernel), bs_func_alias->name,
			    bs_func_alias->original);
	    break;
	}

	case BS_ELEMENT_OPAQUE:
	case BS_ELEMENT_STRUCT:
	{
	    setup_bs_boxed_type(type, value);
	    do_not_free = true;
	    break;
	}

	case BS_ELEMENT_CLASS:
	{
	    bs_element_class_t *bs_class = (bs_element_class_t *)value;
	    bs_element_indexed_class_t *bs_class_new;
	    unsigned i;

	    bs_class_new = (bs_element_indexed_class_t *)
		malloc(sizeof(bs_element_indexed_class_t));

	    bs_class_new->name = bs_class->name;

#define INDEX_METHODS(table, ary, len) \
    do { \
	if (len > 0) { \
	    table = st_init_numtable(); \
	    rb_objc_retain(table); \
	    for (i = 0; i < len; i++) { \
		bs_element_method_t *method = &ary[i]; \
		st_insert(table, (st_data_t)method->name, (st_data_t)method); \
	    } \
	} \
	else { \
	    table = NULL; \
	} \
    } \
    while (0)

	    INDEX_METHODS(bs_class_new->cmethods, bs_class->class_methods,
		bs_class->class_methods_count);

	    INDEX_METHODS(bs_class_new->imethods, bs_class->instance_methods,
		bs_class->instance_methods_count);

#undef INDEX_METHODS

	    st_insert(bs_classes, (st_data_t)bs_class_new->name, 
		(st_data_t)bs_class_new);

	    free(bs_class);
	    do_not_free = true;
	    break;
	}

	case BS_ELEMENT_INFORMAL_PROTOCOL_METHOD:
	{
	    bs_element_informal_protocol_method_t *bs_inf_prot_method = 
		(bs_element_informal_protocol_method_t *)value;
	    struct st_table *t = bs_inf_prot_method->class_method
		? bs_inf_prot_cmethods
		: bs_inf_prot_imethods;

	    st_insert(t, (st_data_t)bs_inf_prot_method->name,
		(st_data_t)bs_inf_prot_method->type);

	    free(bs_inf_prot_method->protocol_name);
	    free(bs_inf_prot_method);
	    do_not_free = true;
	    break;
	}

	case BS_ELEMENT_CFTYPE:
	{
	    bs_element_cftype_t *bs_cftype = (bs_element_cftype_t *)value;
	    st_insert(bs_cftypes, (st_data_t)bs_cftype->type, 
		    (st_data_t)bs_cftype);
	    do_not_free = true;
	    break;
	}
    }

    if (!do_not_free)
	bs_element_free(type, value);
}

static VALUE
rb_objc_load_bs(VALUE recv, VALUE path)
{
    char *error;

    if (!bs_parse(StringValuePtr(path), 0, bs_parse_cb, NULL, &error))
	rb_raise(rb_eRuntimeError, error);

    return recv;
}

static void
load_bridge_support(const char *framework_path)
{
    char path[PATH_MAX];
    char *error;

    if (bs_find_path(framework_path, path, sizeof path)) {
	if (!bs_parse(path, BS_PARSE_OPTIONS_LOAD_DYLIBS, bs_parse_cb, NULL, 
		      &error))
	    rb_raise(rb_eRuntimeError, error);
    }
}

static void
reload_class_constants(void)
{
    static int class_count = 0;
    int i, count;
    Class *buf;

    count = objc_getClassList(NULL, 0);
    if (count == class_count)
	return;

    buf = (Class *)alloca(sizeof(Class) * count);
    objc_getClassList(buf, count);

    for (i = 0; i < count; i++) {
	const char *name = class_getName(buf[i]);
	if (name[0] != '_') {
	    ID id = rb_intern(name);
	    if (!rb_const_defined(rb_cObject, id))
		rb_const_set(rb_cObject, id, rb_objc_class_magic_cookie);
	}
    }

    class_count = count;
}

VALUE
rb_require_framework(int argc, VALUE *argv, VALUE recv)
{
    VALUE framework;
    VALUE search_network;
    const char *cstr;
    NSFileManager *fileManager;
    NSString *path;
    NSBundle *bundle;
    NSError *error;

    rb_scan_args(argc, argv, "11", &framework, &search_network);

    Check_Type(framework, T_STRING);
    cstr = RSTRING_CPTR(framework);

    fileManager = [NSFileManager defaultManager];
    path = [fileManager stringWithFileSystemRepresentation:cstr
	length:strlen(cstr)];

    if (![fileManager fileExistsAtPath:path]) {
	/* framework name is given */
	NSSearchPathDomainMask pathDomainMask;
	NSString *frameworkName;
	NSArray *dirs;
	NSUInteger i, count;

	cstr = NULL;

#define FIND_LOAD_PATH_IN_LIBRARY(dir) 					  \
    do { 								  \
	path = [[dir stringByAppendingPathComponent:@"Frameworks"]	  \
	   stringByAppendingPathComponent:frameworkName];		  \
	if ([fileManager fileExistsAtPath:path])  			  \
	    goto success; 						  \
	path = [[dir stringByAppendingPathComponent:@"PrivateFrameworks"] \
	   stringByAppendingPathComponent:frameworkName];		  \
	if ([fileManager fileExistsAtPath:path]) 			  \
	    goto success; 						  \
    } 									  \
    while(0)

	pathDomainMask = RTEST(search_network)
	    ? NSAllDomainsMask
	    : NSUserDomainMask | NSLocalDomainMask | NSSystemDomainMask;

	frameworkName = [path stringByAppendingPathExtension:@"framework"];

	path = [[[[NSBundle mainBundle] bundlePath] 
	    stringByAppendingPathComponent:@"Contents/Frameworks"] 
		stringByAppendingPathComponent:frameworkName];
	if ([fileManager fileExistsAtPath:path])
	    goto success;	

	dirs = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, 
	    pathDomainMask, YES);
	for (i = 0, count = [dirs count]; i < count; i++) {
	    NSString *dir = [dirs objectAtIndex:i];
	    FIND_LOAD_PATH_IN_LIBRARY(dir);
	}	

	dirs = NSSearchPathForDirectoriesInDomains(NSDeveloperDirectory, 
	    pathDomainMask, YES);
	for (i = 0, count = [dirs count]; i < count; i++) {
	    NSString *dir = [[dirs objectAtIndex:i] 
		stringByAppendingPathComponent:@"Library"];
	    FIND_LOAD_PATH_IN_LIBRARY(dir); 
	}

#undef FIND_LOAD_PATH_IN_LIBRARY

	rb_raise(rb_eRuntimeError, "framework `%s' not found", 
	    RSTRING_CPTR(framework));
    }

success:

    if (cstr == NULL)
	cstr = [path fileSystemRepresentation];

    bundle = [NSBundle bundleWithPath:path];
    if (bundle == nil)
	rb_raise(rb_eRuntimeError, 
	         "framework at path `%s' cannot be located",
		 cstr);

    if ([bundle isLoaded])
	return Qfalse;

    if (![bundle loadAndReturnError:&error]) {
	rb_raise(rb_eRuntimeError,
		 "framework at path `%s' cannot be loaded: %s",
		 cstr,
		 [[error description] UTF8String]); 
    }

    load_bridge_support(cstr);
    reload_class_constants();

    return Qtrue;
}

static const char *
imp_rb_boxed_objCType(void *rcv, SEL sel)
{
    VALUE klass, type;

    klass = CLASS_OF(rcv);
    type = rb_boxed_objc_type(klass);
    
    return StringValuePtr(type);
}

static void
imp_rb_boxed_getValue(void *rcv, SEL sel, void *buffer)
{
    bs_element_boxed_t *bs_boxed;
    void *data;
    bool ok;  

    bs_boxed = rb_klass_get_bs_boxed(CLASS_OF(rcv));

    data = bs_element_boxed_get_data(bs_boxed, (VALUE)rcv, &ok);
    if (!ok)
	[NSException raise:@"NSException" 
	    format:@"can't get internal data for boxed type `%s'",
	    RSTRING_CPTR(rb_inspect((VALUE)rcv))];
    if (data == NULL) {
	*(void **)buffer = NULL; 
    }
    else {
 	memcpy(buffer, data, bs_boxed->ffi_type->size);
    }
}

static inline void
rb_objc_install_method(Class klass, SEL sel, IMP imp)
{
    Method method = class_getInstanceMethod(klass, sel);
    assert(method != NULL);
    assert(class_addMethod(klass, sel, imp, method_getTypeEncoding(method)));
}

static inline void
rb_objc_override_method(Class klass, SEL sel, IMP imp)
{
    Method method = class_getInstanceMethod(klass, sel);
    assert(method != NULL);
    method_setImplementation(method, imp);
}

static void
rb_install_objc_primitives(void)
{
    Class klass;

    /* Boxed */
    klass = RCLASS_OCID(rb_cBoxed);
    rb_objc_override_method(klass, @selector(objCType), 
	(IMP)imp_rb_boxed_objCType);
    rb_objc_override_method(klass, @selector(getValue:), 
	(IMP)imp_rb_boxed_getValue);
}

static void *
rb_objc_allocate(void *klass)
{
    return (void *)rb_obj_alloc(rb_objc_import_class(klass));
}

static void *
imp_rb_obj_alloc(void *rcv, SEL sel)
{
    return rb_objc_allocate(rcv);
}

static void *
imp_rb_obj_allocWithZone(void *rcv, SEL sel, void *zone)
{
    return rb_objc_allocate(rcv);
}

static void *
imp_rb_obj_init(void *rcv, SEL sel)
{
    rb_funcall((VALUE)rcv, idInitialize, 0);
    return rcv;
}

static void
rb_install_alloc_methods(void)
{
    Class klass = RCLASS_OCID(rb_cObject)->isa;

    rb_objc_install_method(klass, @selector(alloc), (IMP)imp_rb_obj_alloc);
    rb_objc_install_method(klass, @selector(allocWithZone:), 
	(IMP)imp_rb_obj_allocWithZone);
    rb_objc_install_method(RCLASS_OCID(rb_cObject), @selector(init), 
	(IMP)imp_rb_obj_init);
}

ID
rb_objc_missing_sel(ID mid, int arity)
{
    const char *name;
    size_t len;
    char buf[100];

    if (mid == 0)
	return mid;

    name = rb_id2name(mid);
    if (name == NULL)
	return mid;

    len = strlen(name);
    if (len == 0)
	return mid;
    
    if (arity == 1 && name[len - 1] == '=') {
	strlcpy(buf, "set", sizeof buf);
	buf[3] = toupper(name[0]);
	buf[4] = '\0';
	strlcat(buf, &name[1], sizeof buf);
	buf[len + 2] = ':';
    }
    else if (arity == 0 && name[len - 1] == '?') {
	strlcpy(buf, "is", sizeof buf);
	buf[2] = toupper(name[0]);
	buf[3] = '\0';
	strlcat(buf, &name[1], sizeof buf);
	buf[len + 1] = '\0';
    }
    else if (arity >= 1 && name[len - 1] != ':' && len < sizeof buf) {
	strlcpy(buf, name, sizeof buf);
	buf[len] = ':';
	buf[len + 1] = '\0';
    }
    else if (arity == 1 && name[len - 1] == ':' && len < sizeof buf) {
	strlcpy(buf, name, sizeof buf);
	buf[len - 1] = '\0';
    }
    else {
	return mid;
    }

    //printf("new sel %s for %s\n", buf, name);

    return rb_intern(buf);	
}

static const char *
resources_path(char *path, size_t len)
{
    CFBundleRef bundle;
    CFURLRef url;

    bundle = CFBundleGetMainBundle();
    assert(bundle != NULL);

    url = CFBundleCopyResourcesDirectoryURL(bundle);
    *path = '-'; 
    *(path+1) = 'I';
    assert(CFURLGetFileSystemRepresentation(
	url, true, (UInt8 *)&path[2], len - 2));
    CFRelease(url);

    return path;
}

int
macruby_main(const char *path, int argc, char **argv)
{
    char **newargv;
    char *p1, *p2;
    int n, i;

    newargv = (char **)malloc(sizeof(char *) * (argc + 2));
    for (i = n = 0; i < argc; i++) {
	if (!strncmp(argv[i], "-psn_", 5) == 0)
	    newargv[n++] = argv[i];
    }
    
    p1 = (char *)malloc(PATH_MAX);
    newargv[n++] = (char *)resources_path(p1, PATH_MAX);

    p2 = (char *)malloc(PATH_MAX);
    snprintf(p2, PATH_MAX, "%s/%s", &p1[2], path);
    newargv[n++] = p2;

    argv = newargv;    
    argc = n;

    ruby_sysinit(&argc, &argv);
    {
	void *tree;
	RUBY_INIT_STACK;
	ruby_init();
	tree = ruby_options(argc, argv);
	free(newargv);
	free(p1);
	free(p2);
	return ruby_run_node(tree);
    }
}

static void
rb_objc_ib_outlet_imp(void *recv, SEL sel, void *value)
{
    const char *selname;
    char buf[128];
    size_t s;   
    VALUE rvalue;

    selname = sel_getName(sel);
    buf[0] = '@';
    buf[1] = tolower(selname[3]);
    s = strlcpy(&buf[2], &selname[4], sizeof buf - 2);
    buf[s + 1] = '\0';

    rb_objc_ocid_to_rval(&value, &rvalue);
    rb_ivar_set((VALUE)recv, rb_intern(buf), rvalue);
}

VALUE
rb_mod_objc_ib_outlet(int argc, VALUE *argv, VALUE recv)
{
    int i;
    char buf[128];

    buf[0] = 's'; buf[1] = 'e'; buf[2] = 't';

    for (i = 0; i < argc; i++) {
	VALUE sym = argv[i];
	const char *symname;
	
	Check_Type(sym, T_SYMBOL);
	symname = rb_id2name(SYM2ID(sym));

	if (strlen(symname) == 0)
	    rb_raise(rb_eArgError, "empty symbol given");
	
	buf[3] = toupper(symname[0]);
	buf[4] = '\0';
	strlcat(buf, &symname[1], sizeof buf);
	strlcat(buf, ":", sizeof buf);

	if (!class_addMethod(RCLASS_OCID(recv), sel_registerName(buf), 
			     (IMP)rb_objc_ib_outlet_imp, "v@:@"))
	    rb_raise(rb_eArgError, "can't register `%s' as an IB outlet",
		     symname);
    }
    return recv;
}

static CFMutableDictionaryRef __obj_flags;

long
rb_objc_flag_get_mask(const void *obj)
{
    if (__obj_flags == NULL)
	return 0;

    return (long)CFDictionaryGetValue(__obj_flags, obj);
}

bool
rb_objc_flag_check(const void *obj, int flag)
{
    long v;

    v = rb_objc_flag_get_mask(obj);
    if (v == 0)
	return false;

    return (v & flag) == flag;
}

void
rb_objc_flag_set(const void *obj, int flag, bool val)
{
    long v;

    if (__obj_flags == NULL) {
	__obj_flags = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    }
    v = (long)CFDictionaryGetValue(__obj_flags, obj);
    if (val) {
	v |= flag;
    }
    else {
	v ^= flag;
    }
    CFDictionarySetValue(__obj_flags, obj, (void *)v);
}

long
rb_objc_remove_flags(const void *obj)
{
    long flag;
    if (CFDictionaryGetValueIfPresent(__obj_flags, obj, 
	(const void **)&flag)) {
	CFDictionaryRemoveValue(__obj_flags, obj);
	return flag;
    }
    return 0;
}

static void
rb_objc_get_types_for_format_str(char **octypes, const int len, VALUE *args,
				 const char *format_str, char **new_fmt)
{
    unsigned i, j, format_str_len;

    format_str_len = strlen(format_str);
    i = j = 0;

    while (i < format_str_len) {
	bool sharp_modifier = false;
	bool star_modifier = false;
	if (format_str[i++] != '%')
	    continue;
	if (i < format_str_len && format_str[i] == '%') {
	    i++;
	    continue;
	}
	while (i < format_str_len) {
	    char *type = NULL;
	    switch (format_str[i]) {
		case '#':
		    sharp_modifier = true;
		    break;

		case '*':
		    star_modifier = true;
		    type = "i"; // C_INT;
		    break;

		case 'd':
		case 'i':
		case 'o':
		case 'u':
		case 'x':
		case 'X':
		    type = "i"; // _C_INT;
		    break;

		case 'c':
		case 'C':
		    type = "c"; // _C_CHR;
		    break;

		case 'D':
		case 'O':
		case 'U':
		    type = "l"; // _C_LNG;
		    break;

		case 'f':       
		case 'F':
		case 'e':       
		case 'E':
		case 'g':       
		case 'G':
		case 'a':
		case 'A':
		    type = "d"; // _C_DBL;
		    break;

		case 's':
		case 'S':
		    {
			if (i - 1 > 0) {
			    long k = i - 1;
			    while (k > 0 && format_str[k] == '0')
				k--;
			    if (k < i && format_str[k] == '.')
				args[j] = (VALUE)CFSTR("");
			}
			type = "*"; // _C_CHARPTR;
		    }
		    break;

		case 'p':
		    type = "^"; // _C_PTR;
		    break;

		case '@':
		    type = "@"; // _C_ID;
		    break;

		case 'B':
		case 'b':
		    {
			VALUE arg = args[j];
			switch (TYPE(arg)) {
			    case T_STRING:
				arg = rb_str_to_inum(arg, 0, Qtrue);
				break;
			}
			arg = rb_big2str(arg, 2);
			if (sharp_modifier) {
			    VALUE prefix = format_str[i] == 'B'
				? (VALUE)CFSTR("0B") : (VALUE)CFSTR("0b");
			   rb_str_update(arg, 0, 0, prefix);
			}
			if (*new_fmt == NULL)
			    *new_fmt = strdup(format_str);
			(*new_fmt)[i] = '@';
			args[j] = arg;
			type = "@"; 
		    }
		    break;
	    }

	    i++;

	    if (type != NULL) {
		if (len == 0 || j >= len)
		    rb_raise(rb_eArgError, 
			"Too much tokens in the format string `%s' "\
			"for the given %d argument(s)", format_str, len);
		octypes[j++] = type;
		if (!star_modifier)
		    break;
	    }
	}
    }
    for (; j < len; j++)
	octypes[j] = "@"; // _C_ID;
}

VALUE
rb_str_format(int argc, const VALUE *argv, VALUE fmt)
{
    char **types;
    ffi_type *ffi_rettype, **ffi_argtypes;
    void *ffi_ret, **ffi_args;
    ffi_cif *cif;
    int i;
    void *null;
    char *new_fmt;

    if (argc == 0)
	return fmt;

    types = (char **)alloca(sizeof(char *) * argc);
    ffi_argtypes = (ffi_type **)alloca(sizeof(ffi_type *) * argc + 4);
    ffi_args = (void **)alloca(sizeof(void *) * argc + 4);

    null = NULL;
    new_fmt = NULL;

    rb_objc_get_types_for_format_str(types, argc, (VALUE *)argv, 
	    RSTRING_CPTR(fmt), &new_fmt);
    if (new_fmt != NULL) {
	fmt = (VALUE)CFStringCreateWithCString(NULL, new_fmt, 
		kCFStringEncodingUTF8);
	free(new_fmt);
	CFMakeCollectable((void *)fmt);
    }  

    for (i = 0; i < argc; i++) {
	ffi_argtypes[i + 3] = rb_objc_octype_to_ffitype(types[i]);
	ffi_args[i + 3] = (void *)alloca(ffi_argtypes[i + 3]->size);
	rb_objc_rval_to_ocval(argv[i], types[i], ffi_args[i + 3]);
    }

    ffi_argtypes[0] = &ffi_type_pointer;
    ffi_args[0] = &null;
    ffi_argtypes[1] = &ffi_type_pointer;
    ffi_args[1] = &null;
    ffi_argtypes[2] = &ffi_type_pointer;
    ffi_args[2] = &fmt;
   
    ffi_argtypes[argc + 4] = NULL;
    ffi_args[argc + 4] = NULL;

    ffi_rettype = &ffi_type_pointer;
    
    cif = (ffi_cif *)alloca(sizeof(ffi_cif));

    if (ffi_prep_cif(cif, FFI_DEFAULT_ABI, argc + 3, ffi_rettype, ffi_argtypes)
        != FFI_OK)
        rb_fatal("can't prepare cif for CFStringCreateWithFormat");

    ffi_ret = NULL;

    ffi_call(cif, FFI_FN(CFStringCreateWithFormat), &ffi_ret, ffi_args);

    if (ffi_ret != NULL) {
        CFMakeCollectable((CFTypeRef)ffi_ret);
        return (VALUE)ffi_ret;
    }
    return Qnil;
}

extern bool __CFStringIsMutable(void *);
extern bool _CFArrayIsMutable(void *);
extern bool _CFDictionaryIsMutable(void *);

bool
rb_objc_is_immutable(VALUE v)
{
    switch(TYPE(v)) {
	case T_STRING:
	    return !__CFStringIsMutable((void *)v);
	case T_ARRAY:
	    return !_CFArrayIsMutable((void *)v);
	case T_HASH:
	    return !_CFDictionaryIsMutable((void *)v);	    
    }
    return false;
}

static void 
timer_cb(CFRunLoopTimerRef timer, void *ctx)
{
    RUBY_VM_CHECK_INTS();
}

void
Init_ObjC(void)
{
    rb_objc_retain(bs_constants = st_init_numtable());
    rb_objc_retain(bs_functions = st_init_numtable());
    rb_objc_retain(bs_function_syms = st_init_numtable());
    rb_objc_retain(bs_boxeds = st_init_strtable());
    rb_objc_retain(bs_classes = st_init_strtable());
    rb_objc_retain(bs_inf_prot_cmethods = st_init_numtable());
    rb_objc_retain(bs_inf_prot_imethods = st_init_numtable());
    rb_objc_retain(bs_cftypes = st_init_strtable());

    rb_objc_retain((const void *)(
	bs_const_magic_cookie = rb_str_new2("bs_const_magic_cookie")));
    rb_objc_retain((const void *)(
	rb_objc_class_magic_cookie = rb_str_new2("rb_objc_class_magic_cookie")));

    rb_cBoxed = rb_define_class("Boxed",
	rb_objc_import_class(objc_getClass("NSValue")));
    rb_define_singleton_method(rb_cBoxed, "objc_type", rb_boxed_objc_type, 0);
    rb_define_singleton_method(rb_cBoxed, "opaque?", rb_boxed_is_opaque, 0);
    rb_define_singleton_method(rb_cBoxed, "fields", rb_boxed_fields, 0);

    rb_ivar_type = rb_intern("@__objc_type__");

    rb_install_objc_primitives();
    rb_install_alloc_methods();

    rb_define_global_function("load_bridge_support_file", rb_objc_load_bs, 1);

    {
	CFRunLoopTimerRef timer;
	timer = CFRunLoopTimerCreate(NULL,
		CFAbsoluteTimeGetCurrent(), 0.1, 0, 0, timer_cb, NULL);
	CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
    }

    rb_define_method(rb_cBasicObject, "__super_objc_send__", rb_super_objc_send, -1);
}

@interface Protocol
@end

@implementation Protocol (MRFindProtocol)
+(id)protocolWithName:(NSString *)name
{
    return (id)objc_getProtocol([name UTF8String]);
} 
@end
