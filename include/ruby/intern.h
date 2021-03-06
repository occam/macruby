/**********************************************************************

  intern.h -

  $Author: nobu $
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifndef RUBY_INTERN_H
#define RUBY_INTERN_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#ifdef HAVE_STDARG_PROTOTYPES
# include <stdarg.h>
#else
# include <varargs.h>
#endif
#if RUBY_INCLUDED_AS_FRAMEWORK
#include <MacRuby/ruby/st.h>
#else
#include <ruby/st.h>
#endif

/* 
 * Functions and variables that are used by more than one source file of
 * the kernel.
 */

#define ID_ALLOCATOR 1

/* array.c */
void rb_mem_clear(register VALUE*, register long);
VALUE rb_assoc_new(VALUE, VALUE);
VALUE rb_check_array_type(VALUE);
VALUE rb_ary_new(void);
VALUE rb_ary_new2(long);
VALUE rb_ary_new3(long,...);
VALUE rb_ary_new4(long, const VALUE *);
void rb_ary_free(VALUE);
VALUE rb_ary_freeze(VALUE);
VALUE rb_ary_subseq(VALUE, long, long);
void rb_ary_store(VALUE, long, VALUE);
VALUE rb_ary_dup(VALUE);
VALUE rb_ary_to_ary(VALUE);
VALUE rb_ary_to_s(VALUE);
VALUE rb_ary_push(VALUE, VALUE);
VALUE rb_ary_pop(VALUE);
VALUE rb_ary_shift(VALUE);
VALUE rb_ary_unshift(VALUE, VALUE);
VALUE rb_ary_entry(VALUE, long);
VALUE rb_ary_join(VALUE, VALUE);
VALUE rb_ary_print_on(VALUE, VALUE);
VALUE rb_ary_reverse(VALUE);
VALUE rb_ary_sort(VALUE);
VALUE rb_ary_sort_bang(VALUE);
VALUE rb_ary_delete(VALUE, VALUE);
VALUE rb_ary_delete_at(VALUE, long);
VALUE rb_ary_clear(VALUE);
VALUE rb_ary_plus(VALUE, VALUE);
VALUE rb_ary_concat(VALUE, VALUE);
VALUE rb_ary_includes(VALUE, VALUE);
VALUE rb_ary_replace(VALUE copy, VALUE orig);
VALUE rb_get_values_at(VALUE, long, int, VALUE*, VALUE(*)(VALUE,long));
void rb_ary_insert(VALUE, long, VALUE);
VALUE rb_ary_equal(VALUE, VALUE);
#if WITH_OBJC
long rb_ary_len(VALUE);
VALUE rb_ary_elt(VALUE, long);
VALUE rb_ary_aref(VALUE ary, SEL sel, int argc, VALUE *argv);
bool rb_objc_ary_is_pure(VALUE);
#endif
/* bignum.c */
VALUE rb_big_clone(VALUE);
void rb_big_2comp(VALUE);
VALUE rb_big_norm(VALUE);
void rb_big_resize(VALUE big, long len);
VALUE rb_uint2big(VALUE);
VALUE rb_int2big(SIGNED_VALUE);
VALUE rb_uint2inum(VALUE);
VALUE rb_int2inum(SIGNED_VALUE);
VALUE rb_cstr_to_inum(const char*, int, int);
VALUE rb_str_to_inum(VALUE, int, int);
VALUE rb_cstr2inum(const char*, int);
VALUE rb_str2inum(VALUE, int);
VALUE rb_big2str(VALUE, int);
VALUE rb_big2str0(VALUE, int, int);
SIGNED_VALUE rb_big2long(VALUE);
#define rb_big2int(x) rb_big2long(x)
VALUE rb_big2ulong(VALUE);
#define rb_big2uint(x) rb_big2ulong(x)
#if HAVE_LONG_LONG
VALUE rb_ll2inum(LONG_LONG);
VALUE rb_ull2inum(unsigned LONG_LONG);
LONG_LONG rb_big2ll(VALUE);
unsigned LONG_LONG rb_big2ull(VALUE);
#endif  /* HAVE_LONG_LONG */
void rb_quad_pack(char*,VALUE);
VALUE rb_quad_unpack(const char*,int);
int rb_uv_to_utf8(char[6],unsigned long);
VALUE rb_dbl2big(double);
double rb_big2dbl(VALUE);
VALUE rb_big_cmp(VALUE, VALUE);
VALUE rb_big_eq(VALUE, VALUE);
VALUE rb_big_plus(VALUE, VALUE);
VALUE rb_big_minus(VALUE, VALUE);
VALUE rb_big_mul(VALUE, VALUE);
VALUE rb_big_div(VALUE, VALUE);
VALUE rb_big_modulo(VALUE, VALUE);
VALUE rb_big_divmod(VALUE, VALUE);
VALUE rb_big_pow(VALUE, VALUE);
VALUE rb_big_and(VALUE, VALUE);
VALUE rb_big_or(VALUE, VALUE);
VALUE rb_big_xor(VALUE, VALUE);
VALUE rb_big_lshift(VALUE, VALUE);
VALUE rb_big_rshift(VALUE, VALUE);
/* rational.c */
VALUE rb_rational_raw(VALUE, VALUE);
#define rb_rational_raw1(x) rb_rational_raw(x, INT2FIX(1))
#define rb_rational_raw2(x,y) rb_rational_raw(x, y)
VALUE rb_rational_new(VALUE, VALUE);
#define rb_rational_new1(x) rb_rational_new(x, INT2FIX(1))
#define rb_rational_new2(x,y) rb_rational_new(x, y)
VALUE rb_Rational(VALUE, VALUE);
#define rb_Rational1(x) rb_Rational(x, INT2FIX(1))
#define rb_Rational2(x,y) rb_Rational(x, y)
/* complex.c */
VALUE rb_complex_raw(VALUE, VALUE);
#define rb_complex_raw1(x) rb_complex_raw(x, INT2FIX(0))
#define rb_complex_raw2(x,y) rb_complex_raw(x, y)
VALUE rb_complex_new(VALUE, VALUE);
#define rb_complex_new1(x) rb_complex_new(x, INT2FIX(0))
#define rb_complex_new2(x,y) rb_complex_new(x, y)
VALUE rb_Complex(VALUE, VALUE);
#define rb_Complex1(x) rb_Complex(x, INT2FIX(0))
#define rb_Complex2(x,y) rb_Complex(x, y)
/* class.c */
#if WITH_OBJC
VALUE rb_objc_create_class(const char *name, VALUE super);
bool rb_objc_install_primitives(Class ocklass, Class ocsuper);
void rb_define_object_special_methods(VALUE klass);
#endif
VALUE rb_class_boot(VALUE);
VALUE rb_class_new(VALUE);
//VALUE rb_mod_init_copy(VALUE, VALUE);
//VALUE rb_class_init_copy(VALUE, VALUE);
VALUE rb_singleton_class_clone(VALUE);
void rb_singleton_class_attached(VALUE,VALUE);
VALUE rb_make_metaclass(VALUE, VALUE);
void rb_check_inheritable(VALUE);
VALUE rb_class_inherited(VALUE, VALUE);
VALUE rb_define_class_id(ID, VALUE);
VALUE rb_module_new(void);
VALUE rb_define_module_id(ID);
VALUE rb_mod_included_modules(VALUE);
//VALUE rb_mod_include_p(VALUE, VALUE);
VALUE rb_mod_ancestors(VALUE);
VALUE rb_mod_ancestors_nocopy(VALUE);
//VALUE rb_class_instance_methods(int, VALUE*, VALUE);
//VALUE rb_class_public_instance_methods(int, VALUE*, VALUE);
//VALUE rb_class_protected_instance_methods(int, VALUE*, VALUE);
//VALUE rb_class_private_instance_methods(int, VALUE*, VALUE);
//VALUE rb_obj_singleton_methods(int, VALUE*, VALUE);
void rb_define_method_id(VALUE, ID, VALUE (*)(ANYARGS), int);
void rb_frozen_class_p(VALUE);
void rb_undef(VALUE, ID);
void rb_define_protected_method(VALUE, const char*, VALUE (*)(ANYARGS), int);
void rb_define_private_method(VALUE, const char*, VALUE (*)(ANYARGS), int);
void rb_define_singleton_method(VALUE, const char*, VALUE(*)(ANYARGS), int);
VALUE rb_singleton_class(VALUE);
/* compar.c */
int rb_cmpint(VALUE, VALUE, VALUE);
NORETURN(void rb_cmperr(VALUE, VALUE));
VALUE rb_objs_cmp(VALUE x, VALUE y);
/* cont.c */
VALUE rb_fiber_new(VALUE (*)(ANYARGS), VALUE);
VALUE rb_fiber_resume(VALUE fib, int argc, VALUE *args);
VALUE rb_fiber_yield(int argc, VALUE *args);
VALUE rb_fiber_current(void);
VALUE rb_fiber_alive_p(VALUE);
/* enum.c */
/* enumerator.c */
VALUE rb_enumeratorize(VALUE, SEL, int, VALUE *);
#define RETURN_ENUMERATOR(obj, argc, argv) do {				\
	if (!rb_block_given_p())					\
	    return rb_enumeratorize(obj, sel, argc, argv);		\
    } while (0)
/* error.c */
VALUE rb_exc_new(VALUE, const char*, long);
VALUE rb_exc_new2(VALUE, const char*);
VALUE rb_exc_new3(VALUE, VALUE);
PRINTF_ARGS(NORETURN(void rb_loaderror(const char*, ...)), 1, 2);
PRINTF_ARGS(NORETURN(void rb_name_error(ID, const char*, ...)), 2, 3);
NORETURN(void rb_invalid_str(const char*, const char*));
PRINTF_ARGS(void rb_compile_error(const char*, int, const char*, ...), 3, 4);
PRINTF_ARGS(void rb_compile_error_append(const char*, ...), 1, 2);
NORETURN(void rb_load_fail(const char*));
NORETURN(void rb_error_frozen(const char*));
void rb_check_frozen(VALUE);
/* eval.c */
VALUE rb_make_exception(int, VALUE *);
int rb_sourceline(void);
const char *rb_sourcefile(void);

#if defined(NFDBITS) && defined(HAVE_RB_FD_INIT)
typedef struct {
    int maxfd;
    fd_set *fdset;
} rb_fdset_t;

void rb_fd_init(volatile rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
void rb_fd_zero(rb_fdset_t *);
void rb_fd_set(int, rb_fdset_t *);
void rb_fd_clr(int, rb_fdset_t *);
int rb_fd_isset(int, const rb_fdset_t *);
void rb_fd_copy(rb_fdset_t *, const fd_set *, int);
int rb_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);

#define rb_fd_ptr(f)	((f)->fdset)
#define rb_fd_max(f)	((f)->maxfd)

#else

typedef fd_set rb_fdset_t;
#define rb_fd_zero(f)	FD_ZERO(f)
#define rb_fd_set(n, f)	FD_SET(n, f)
#define rb_fd_clr(n, f)	FD_CLR(n, f)
#define rb_fd_isset(n, f) FD_ISSET(n, f)
#define rb_fd_copy(d, s, n) (*(d) = *(s))
#define rb_fd_ptr(f)	(f)
#define rb_fd_init(f)	FD_ZERO(f)
#define rb_fd_term(f)	(void)(f)
#define rb_fd_max(f)	FD_SETSIZE
#define rb_fd_select(n, rfds, wfds, efds, timeout)	select(n, rfds, wfds, efds, timeout)

#endif

NORETURN(void rb_exc_raise(VALUE));
NORETURN(void rb_exc_fatal(VALUE));
void rb_remove_method(VALUE, const char*);
#define rb_disable_super(klass, name) ((void)0)
#define rb_enable_super(klass, name) ((void)0)
#define HAVE_RB_DEFINE_ALLOC_FUNC 1
typedef VALUE (*rb_alloc_func_t)(VALUE);
void rb_define_alloc_func(VALUE, rb_alloc_func_t);
void rb_undef_alloc_func(VALUE);
rb_alloc_func_t rb_get_alloc_func(VALUE);
void rb_clear_cache(void);
void rb_clear_cache_by_class(VALUE);
void rb_alias(VALUE, ID, ID);
void rb_attr(VALUE,ID,int,int,int);
int rb_method_boundp(VALUE, ID, int);
VALUE rb_eval_cmd(VALUE, VALUE, int);
bool rb_obj_respond_to(VALUE, ID, bool);
bool rb_respond_to(VALUE, ID);
void rb_interrupt(void);
VALUE rb_apply(VALUE, ID, VALUE);
void rb_backtrace(void);
ID rb_frame_this_func(void);
void rb_load(VALUE, int);
NORETURN(void rb_jump_tag(int));
int rb_provided(const char*);
VALUE rb_f_require(VALUE, VALUE);
VALUE rb_require_safe(VALUE, int);
VALUE rb_obj_call_init(VALUE, int, VALUE*);
VALUE rb_class_new_instance(int, VALUE*, VALUE);
VALUE rb_block_proc(void);
VALUE rb_f_lambda(void);
VALUE rb_proc_call(VALUE, VALUE);
int rb_proc_arity(VALUE);
VALUE rb_binding_new(void);
VALUE rb_method_call(VALUE, SEL, int, VALUE*);
int rb_mod_method_arity(VALUE, ID);
int rb_obj_method_arity(VALUE, ID);
VALUE rb_protect(VALUE (*)(VALUE), VALUE, int*);
void rb_set_end_proc(void (*)(VALUE), VALUE);
void rb_mark_end_proc(void);
void rb_exec_end_proc(void);
void Init_jump(void);
void ruby_finalize(void);
NORETURN(void ruby_stop(int));
int ruby_cleanup(int);
void rb_gc_mark_threads(void);
void rb_thread_schedule(void);
void rb_thread_wait_fd(int);
int rb_thread_fd_writable(int);
void rb_thread_fd_close(int);
int rb_thread_alone(void);
void rb_thread_polling(void);
void rb_thread_sleep(int);
void rb_thread_sleep_forever(void);
VALUE rb_thread_create(VALUE (*)(ANYARGS), void*);
void rb_thread_signal_raise(void *, int);
void rb_thread_signal_exit(void *);
int rb_thread_select(int, fd_set *, fd_set *, fd_set *, struct timeval *);
void rb_thread_wait_for(struct timeval);
VALUE rb_thread_current(void);
VALUE rb_thread_main(void);
VALUE rb_thread_local_aref(VALUE, ID);
VALUE rb_thread_local_aset(VALUE, ID, VALUE);
void rb_thread_atfork(void);
void rb_thread_atfork_before_exec(void);
VALUE rb_exec_recursive(VALUE(*)(VALUE, VALUE, int),VALUE,VALUE);
/* file.c */
VALUE rb_file_expand_path(VALUE, VALUE);
void rb_file_const(const char*, VALUE);
int rb_find_file_ext(VALUE*, const char* const*);
VALUE rb_find_file(VALUE);
#define rb_path_skip_prefix(path) (path)
char *rb_path_end(const char *);
VALUE rb_file_directory_p(VALUE,SEL,VALUE);
/* gc.c */
void ruby_set_stack_size(size_t);
NORETURN(void rb_memerror(void));
int ruby_stack_check(void);
int ruby_stack_length(VALUE**);
#if WITH_OBJC
void rb_objc_gc_register_thread(void);
void rb_objc_gc_unregister_thread(void);
void rb_objc_set_associative_ref(void *, void *, void *);
void *rb_objc_get_associative_ref(void *, void *);
const void *rb_objc_retain(const void *);
const void *rb_objc_release(const void *);
# define rb_gc_mark_locations(x,y)
# define rb_mark_tbl(x)
# define rb_mark_set(x)
# define rb_mark_hash(x)
# define rb_gc_mark_maybe(x)
# define rb_gc_mark(x)
#else
void rb_gc_mark_locations(VALUE*, VALUE*);
void rb_mark_tbl(struct st_table*);
void rb_mark_set(struct st_table*);
void rb_mark_hash(struct st_table*);
void rb_gc_mark_maybe(VALUE);
void rb_gc_mark(VALUE);
#endif
void rb_gc_force_recycle(VALUE);
void rb_gc(void);
void rb_gc_copy_finalizer(VALUE,VALUE);
void rb_gc_finalize_deferred(void);
void rb_gc_call_finalizer_at_exit(void);
//VALUE rb_gc_enable(void);
//VALUE rb_gc_disable(void);
//VALUE rb_gc_start(void);
/* hash.c */
void st_foreach_safe(struct st_table *, int (*)(ANYARGS), st_data_t);
void rb_hash_foreach(VALUE, int (*)(ANYARGS), VALUE);
VALUE rb_hash(VALUE);
VALUE rb_hash_new(void);
VALUE rb_hash_new2(int argc, const VALUE *argv);
VALUE rb_hash_dup(VALUE);
VALUE rb_hash_freeze(VALUE);
VALUE rb_hash_aref(VALUE, VALUE);
VALUE rb_hash_lookup(VALUE, VALUE);
VALUE rb_hash_aset(VALUE, VALUE, VALUE);
//VALUE rb_hash_delete_if(VALUE);
VALUE rb_hash_delete(VALUE,VALUE);
VALUE rb_hash_delete_key(VALUE,VALUE);
VALUE rb_hash_has_key(VALUE hash, VALUE key);
VALUE rb_hash_keys(VALUE hash);
struct st_table *rb_hash_tbl(VALUE);
int rb_path_check(const char*);
int rb_env_path_tainted(void);
VALUE rb_env_clear(void);
#if WITH_OBJC
bool rb_objc_hash_is_pure(VALUE);
#endif
/* io.c */
#define rb_defout rb_stdout
RUBY_EXTERN VALUE rb_fs;
RUBY_EXTERN VALUE rb_output_fs;
RUBY_EXTERN VALUE rb_rs;
RUBY_EXTERN VALUE rb_default_rs;
RUBY_EXTERN VALUE rb_output_rs;
VALUE rb_io_write(VALUE, SEL, VALUE);
VALUE rb_io_gets(VALUE, SEL);
VALUE rb_io_getbyte(VALUE, SEL);
VALUE rb_io_ungetc(VALUE, SEL, VALUE);
VALUE rb_io_close(VALUE);
VALUE rb_io_flush(VALUE, SEL);
VALUE rb_io_eof(VALUE, SEL);
VALUE rb_io_binmode(VALUE, SEL);
VALUE rb_io_addstr(VALUE, SEL, VALUE);
VALUE rb_io_printf(VALUE, SEL, int, VALUE *);
VALUE rb_io_print(VALUE, SEL, int, VALUE *);
VALUE rb_io_fdopen(int, int, const char*);
VALUE rb_gets(void);
void rb_write_error(const char*);
void rb_write_error2(const char*, long);
int rb_io_mode_modenum(const char *mode);
void rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds);
/* marshal.c */
VALUE rb_marshal_dump(VALUE, VALUE);
VALUE rb_marshal_load(VALUE);
void rb_marshal_define_compat(VALUE newclass, VALUE oldclass, VALUE (*dumper)(VALUE), VALUE (*loader)(VALUE, VALUE));
/* numeric.c */
void rb_num_zerodiv(void);
VALUE rb_num_coerce_bin(VALUE, VALUE, ID);
VALUE rb_objc_num_coerce_bin(VALUE x, VALUE Y, SEL sel);
VALUE rb_num_coerce_cmp(VALUE, VALUE, ID);
VALUE rb_objc_num_coerce_cmp(VALUE, VALUE, SEL sel);
VALUE rb_num_coerce_relop(VALUE, VALUE, SEL);
VALUE rb_float_new(double);
VALUE rb_num2fix(VALUE);
VALUE rb_fix2str(VALUE, int);
VALUE rb_dbl_cmp(double, double);
/* object.c */
VALUE rb_send_dup(VALUE);
int rb_eql(VALUE, VALUE);
VALUE rb_any_to_s(VALUE);
VALUE rb_inspect(VALUE);
VALUE rb_obj_is_instance_of(VALUE, VALUE);
VALUE rb_obj_is_kind_of(VALUE, VALUE);
VALUE rb_obj_alloc(VALUE);
VALUE rb_obj_clone(VALUE);
VALUE rb_obj_dup(VALUE);
//VALUE rb_obj_init_copy(VALUE,VALUE);
VALUE rb_obj_taint(VALUE);
VALUE rb_obj_tainted(VALUE);
VALUE rb_obj_untaint(VALUE);
VALUE rb_obj_trust(VALUE);
VALUE rb_obj_untrust(VALUE);
VALUE rb_obj_untrusted(VALUE);
VALUE rb_obj_freeze(VALUE);
VALUE rb_obj_frozen_p(VALUE);
//VALUE rb_obj_id(VALUE);
VALUE rb_obj_class(VALUE);
VALUE rb_class_real(VALUE);
VALUE rb_class_inherited_p(VALUE, VALUE);
VALUE rb_convert_type(VALUE,int,const char*,const char*);
VALUE rb_check_convert_type(VALUE,int,const char*,const char*);
VALUE rb_check_to_integer(VALUE, const char *);
VALUE rb_to_int(VALUE);
VALUE rb_Integer(VALUE);
VALUE rb_Float(VALUE);
VALUE rb_String(VALUE);
VALUE rb_Array(VALUE);
double rb_cstr_to_dbl(const char*, int);
double rb_str_to_dbl(VALUE, int);
/* parse.y */
RUBY_EXTERN int   ruby_sourceline;
RUBY_EXTERN char *ruby_sourcefile;
ID rb_id_attrset(ID);
void rb_gc_mark_parser(void);
int rb_is_const_id(ID);
int rb_is_instance_id(ID);
int rb_is_class_id(ID);
int rb_is_local_id(ID);
int rb_is_junk_id(ID);
int rb_symname_p(const char*);
int rb_sym_interned_p(VALUE);
void rb_gc_mark_symbols(void);
VALUE rb_backref_get(void);
void rb_backref_set(VALUE);
VALUE rb_lastline_get(void);
void rb_lastline_set(VALUE);
VALUE rb_sym_all_symbols(void);
/* process.c */
void rb_last_status_set(int status, rb_pid_t pid);
VALUE rb_last_status_get(void);
struct rb_exec_arg {
    int argc;
    VALUE *argv;
    const char *prog;
    VALUE options;
    VALUE redirect_fds;
};
int rb_proc_exec_n(int, VALUE*, const char*);
int rb_proc_exec(const char*);
VALUE rb_exec_arg_init(int argc, VALUE *argv, int accept_shell, struct rb_exec_arg *e);
int rb_exec_arg_addopt(struct rb_exec_arg *e, VALUE key, VALUE val);
void rb_exec_arg_fixup(struct rb_exec_arg *e);
int rb_run_exec_options(const struct rb_exec_arg *e, struct rb_exec_arg *s);
int rb_exec(const struct rb_exec_arg*);
rb_pid_t rb_fork(int*, int (*)(void*), void*, VALUE);
rb_pid_t rb_waitpid(rb_pid_t pid, int *status, int flags);
void rb_syswait(rb_pid_t pid);
rb_pid_t rb_spawn(int, VALUE*);
VALUE rb_detach_process(rb_pid_t pid);
/* range.c */
void rb_range_extract(VALUE range, VALUE *begp, VALUE *endp, bool *exclude);
VALUE rb_range_new(VALUE, VALUE, int);
VALUE rb_range_beg_len(VALUE, long*, long*, long, int);
/* random.c */
unsigned long rb_genrand_int32(void);
double rb_genrand_real(void);
/* re.c */
#define rb_memcmp memcmp
int rb_memcicmp(const void*,const void*,long);
VALUE rb_reg_nth_defined(int, VALUE);
VALUE rb_reg_nth_match(int, VALUE);
VALUE rb_reg_last_match(VALUE);
VALUE rb_reg_match_last(VALUE);
#define HAVE_RB_REG_NEW_STR 1
VALUE rb_reg_new_str(VALUE, int);
VALUE rb_reg_new(const char *, long, int);
VALUE rb_reg_match(VALUE, VALUE);
int rb_reg_options(VALUE);
VALUE rb_reg_eqq(VALUE, SEL, VALUE);
void rb_set_kcode(const char*);
const char* rb_get_kcode(void);
/* ruby.c */
#define rb_argv rb_get_argv()
RUBY_EXTERN VALUE rb_argv0;
VALUE rb_get_argv(void);
void *rb_load_file(const char*);
void ruby_script(const char*);
void ruby_prog_init(void);
void ruby_set_argv(int, char**);
void *ruby_process_options(int, char**);
void ruby_init_loadpath(void);
void ruby_incpush(const char*);
/* signal.c */
VALUE rb_f_kill(VALUE, SEL, int, VALUE*);
void rb_gc_mark_trap_list(void);
#ifdef POSIX_SIGNAL
#define posix_signal ruby_posix_signal
RETSIGTYPE (*posix_signal(int, RETSIGTYPE (*)(int)))(int);
#endif
void ruby_sig_finalize(void);
void rb_trap_exit(void);
void rb_trap_exec(void);
const char *ruby_signal_name(int);
void ruby_default_signal(int);
/* sprintf.c */
VALUE rb_f_sprintf(int, const VALUE*);
PRINTF_ARGS(VALUE rb_sprintf(const char*, ...), 1, 2);
VALUE rb_vsprintf(const char*, va_list);
VALUE rb_str_format(int, const VALUE *, VALUE);
/* string.c */
VALUE rb_str_new(const char*, long);
VALUE rb_str_new2(const char*);
VALUE rb_str_new3(VALUE);
VALUE rb_str_new4(VALUE);
VALUE rb_str_new5(VALUE, const char*, long);
VALUE rb_tainted_str_new(const char*, long);
VALUE rb_tainted_str_new2(const char*);
VALUE rb_str_buf_new(long);
VALUE rb_str_buf_new2(const char*);
VALUE rb_str_tmp_new(long);
VALUE rb_usascii_str_new(const char*, long);
VALUE rb_usascii_str_new2(const char*);
void rb_str_free(VALUE);
void rb_str_shared_replace(VALUE, VALUE);
VALUE rb_str_buf_append(VALUE, VALUE);
VALUE rb_str_buf_cat(VALUE, const char*, long);
VALUE rb_str_buf_cat2(VALUE, const char*);
VALUE rb_str_buf_cat_ascii(VALUE, const char*);
VALUE rb_obj_as_string(VALUE);
VALUE rb_check_string_type(VALUE);
VALUE rb_str_dup(VALUE);
VALUE rb_str_locktmp(VALUE);
VALUE rb_str_unlocktmp(VALUE);
VALUE rb_str_dup_frozen(VALUE);
long rb_str_sublen(VALUE, long);
VALUE rb_str_substr(VALUE, long, long);
VALUE rb_str_subseq(VALUE, long, long);
void rb_str_modify(VALUE);
VALUE rb_str_freeze(VALUE);
void rb_str_set_len(VALUE, long);
VALUE rb_str_resize(VALUE, long);
VALUE rb_str_cat(VALUE, const char*, long);
VALUE rb_str_cat2(VALUE, const char*);
VALUE rb_str_append(VALUE, VALUE);
VALUE rb_str_concat(VALUE, VALUE);
int rb_memhash(const void *ptr, long len);
int rb_str_hash(VALUE);
int rb_str_hash_cmp(VALUE,VALUE);
int rb_str_comparable(VALUE, VALUE);
int rb_str_cmp(VALUE, VALUE);
VALUE rb_str_equal(VALUE str1, VALUE str2);
void rb_str_update(VALUE, long, long, VALUE);
VALUE rb_str_split(VALUE, const char*);
void rb_str_associate(VALUE, VALUE);
VALUE rb_str_associated(VALUE);
void rb_str_setter(VALUE, ID, VALUE*);
VALUE rb_sym_to_s(VALUE);
VALUE rb_str_length(VALUE);
#if WITH_OBJC
bool rb_objc_str_is_pure(VALUE);
#endif
/* struct.c */
VALUE rb_struct_new(VALUE, ...);
VALUE rb_struct_define(const char*, ...);
VALUE rb_struct_alloc(VALUE, VALUE);
VALUE rb_struct_initialize(VALUE, SEL, VALUE);
VALUE rb_struct_aref(VALUE, VALUE);
VALUE rb_struct_aset(VALUE, VALUE, VALUE);
VALUE rb_struct_getmember(VALUE, ID);
VALUE rb_struct_iv_get(VALUE, const char*);
VALUE rb_struct_s_members(VALUE);
VALUE rb_struct_members(VALUE);
VALUE rb_struct_alloc_noinit(VALUE);
VALUE rb_struct_define_without_accessor(const char *, VALUE, rb_alloc_func_t, ...);
/* thread.c */
VALUE rb_thgroup_add(VALUE group, VALUE thread);
typedef void rb_unblock_function_t(void *);
typedef VALUE rb_blocking_function_t(void *);
VALUE rb_thread_blocking_region(rb_blocking_function_t *func, void *data1,
				rb_unblock_function_t *ubf, void *data2);
#define RB_UBF_DFL ((rb_unblock_function_t *)-1)
VALUE rb_barrier_new(void);
VALUE rb_barrier_wait(VALUE self);
VALUE rb_barrier_release(VALUE self);
/* time.c */
VALUE rb_time_new(time_t, long);
VALUE rb_time_nano_new(time_t, long);
struct timeval rb_time_interval(VALUE num);
/* variable.c */
//VALUE rb_mod_name(VALUE);
VALUE rb_class_path(VALUE);
void rb_set_class_path(VALUE, VALUE, const char*);
void rb_set_class_path2(VALUE, VALUE, const char*, bool);
VALUE rb_path2class(const char*);
void rb_name_class(VALUE, ID);
VALUE rb_class_name(VALUE);
void rb_autoload(VALUE, ID, const char*);
VALUE rb_autoload_load(VALUE, ID);
VALUE rb_autoload_p(VALUE, ID);
void rb_gc_mark_global_tbl(void);
void rb_alias_variable(ID, ID);
struct st_table* rb_generic_ivar_table(VALUE);
void rb_copy_generic_ivar(VALUE,VALUE);
void rb_mark_generic_ivar(VALUE);
void rb_mark_generic_ivar_tbl(void);
void rb_free_generic_ivar(VALUE);
VALUE rb_ivar_get(VALUE, ID);
VALUE rb_ivar_set(VALUE, ID, VALUE);
VALUE rb_ivar_defined(VALUE, ID);
void rb_ivar_foreach(VALUE, int (*)(ANYARGS), st_data_t);
VALUE rb_iv_set(VALUE, const char*, VALUE);
VALUE rb_iv_get(VALUE, const char*);
VALUE rb_attr_get(VALUE, ID);
VALUE rb_obj_instance_variables(VALUE);
//VALUE rb_obj_remove_instance_variable(VALUE, VALUE);
void *rb_mod_const_at(VALUE, void*);
void *rb_mod_const_of(VALUE, void*);
VALUE rb_const_list(void*);
//VALUE rb_mod_constants(int, VALUE *, VALUE);
VALUE rb_mod_remove_const(VALUE, VALUE);
int rb_const_defined(VALUE, ID);
int rb_const_defined_at(VALUE, ID);
int rb_const_defined_from(VALUE, ID);
VALUE rb_const_get(VALUE, ID);
VALUE rb_const_get_at(VALUE, ID);
VALUE rb_const_get_from(VALUE, ID);
void rb_const_set(VALUE, ID, VALUE);
//VALUE rb_mod_const_missing(VALUE,VALUE);
VALUE rb_cvar_defined(VALUE, ID);
void rb_cvar_set(VALUE, ID, VALUE);
VALUE rb_cvar_get(VALUE, ID);
VALUE rb_cvar_get2(VALUE klass, ID id, bool check);
void rb_cv_set(VALUE, const char*, VALUE);
VALUE rb_cv_get(VALUE, const char*);
void rb_define_class_variable(VALUE, const char*, VALUE);
//VALUE rb_mod_class_variables(VALUE);
//VALUE rb_mod_remove_cvar(VALUE, VALUE);
/* objc.m */
#if WITH_OBJC
void rb_objc_alias(VALUE, ID, ID);
VALUE rb_mod_objc_ancestors(VALUE);
//VALUE rb_mod_objc_ib_outlet(int, VALUE *, VALUE);
VALUE rb_require_framework(VALUE, SEL, int, VALUE *);
VALUE rb_objc_resolve_const_value(VALUE, VALUE, ID);
ID rb_objc_missing_sel(ID, int);
long rb_objc_flag_get_mask(const void *);
void rb_objc_flag_set(const void *, int, bool);
bool rb_objc_flag_check(const void *, int);
long rb_objc_remove_flags(const void *obj);
void rb_objc_methods(VALUE, Class);
bool rb_objc_is_immutable(VALUE);
#endif
/* version.c */
void ruby_show_version(void);
void ruby_show_copyright(void);

ID rb_frame_callee(void);
VALUE rb_time_succ(VALUE);
void Init_stack(VALUE*);
void rb_frame_pop(void);
int rb_frame_method_id_and_class(ID *idp, VALUE *klassp);

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_INTERN_H */
