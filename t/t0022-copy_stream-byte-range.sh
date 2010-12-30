#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
case $RUBY_VERSION in
1.9.*) ;;
*)
	t_info "skipping $T since it can't IO.copy_stream"
	exit 0
	;;
esac

case $model in
ThreadSpawn|WriterThreadSpawn|ThreadPool|WriterThreadPool|Base) ;;
*)
	t_info "skipping $T since it doesn't use IO.copy_stream"
	exit 0
	;;
esac

t_plan 11 "IO.copy_stream byte range response for $model"

t_begin "setup and startup" && {
	rtmpfiles out err
	rainbows_setup $model
	# can't load Rack::Lint here since it clobbers body#to_path
	rainbows -E none -D large-file-response.ru -c $unicorn_config
	rainbows_wait_start
	random_blob_size=$(wc -c < random_blob)
	rb_1=$(( $random_blob_size - 1 ))
	range_head=-r-365
	range_tail=-r155-
	range_mid=-r200-300
	range_n1=-r0-$rb_1
	range_n2=-r0-$(($rb_1 - 1))
	range_1b_head=-r0-0
	range_1b_tail=-r$rb_1-$rb_1
	range_1b_mid=-r200-200
	range_all=-r0-$random_blob_size
	url=http://$listen/random_blob
}

check_content_range () {
	# Content-Range: bytes #{offset}-#{offset+count-1}/#{clen}
	d='\([0-9]\+\)'
	start= end= size=
	eval $(< $err sed -n -e \
	  "s/^< Content-Range: bytes $d-$d\/$d"'.*$/start=\1 end=\2 size=\3/p')
	test -n "$start"
	test -n "$end"
	test -n "$size"

	# ensure we didn't screw up the sed invocation
	expect="< Content-Range: bytes $start-$end/$size"
	test x"$(grep -F "$expect" $err)" = x"$(grep '^< Content-Range:' $err)"

	test $start -le $end
	test $end -lt $size
	grep 'Range:' $err
}

t_begin "read random blob sha1s" && {
	sha1_head=$(curl -sSff $range_head file://random_blob | rsha1)
	sha1_tail=$(curl -sSff $range_tail file://random_blob | rsha1)
	sha1_mid=$(curl -sSff $range_mid file://random_blob | rsha1)
	sha1_n1=$(curl -sSff $range_n1 file://random_blob | rsha1)
	sha1_n2=$(curl -sSff $range_n2 file://random_blob | rsha1)
	sha1_1b_head=$(curl -sSff $range_1b_head file://random_blob | rsha1)
	sha1_1b_tail=$(curl -sSff $range_1b_tail file://random_blob | rsha1)
	sha1_1b_mid=$(curl -sSff $range_1b_mid file://random_blob | rsha1)
	sha1_all=$(rsha1 < random_blob)
	echo "$sha1_all=$sha1_n1"
}

t_begin "normal full request matches" && {
	sha1="$(curl -v 2>$err -sSf $url | rsha1)"
	test x"$sha1_all" = x"$sha1"
	grep 'Content-Range:' $err && die "Content-Range unexpected"
	grep 'HTTP/1.1 200 OK' $err || die "200 response expected"
}

t_begin "crazy offset goes over" && {
	range_insane=-r$(($random_blob_size * 2))-$(($random_blob_size * 4))
	curl -vsS 2>$err $range_insane $url
	grep 'HTTP/1\.[01] 416 ' $err || die "expected 416 error"
}

t_begin "full request matches with explicit ranges" && {
	sha1="$(curl -v 2>$err $range_all -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_all" = x"$sha1"

	sha1="$(curl -v 2>$err $range_n1 -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_all" = x"$sha1"

	range_over=-r0-$(($random_blob_size * 2))
	sha1="$(curl -v 2>$err $range_over -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_all" = x"$sha1"
}

t_begin "no fence post errors" && {
	sha1="$(curl -v 2>$err $range_n2 -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_n2" = x"$sha1"

	sha1="$(curl -v 2>$err $range_1b_head -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_1b_head" = x"$sha1"

	sha1="$(curl -v 2>$err $range_1b_tail -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_1b_tail" = x"$sha1"

	sha1="$(curl -v 2>$err $range_1b_mid -sSf $url | rsha1)"
	check_content_range
	test x"$sha1_1b_mid" = x"$sha1"
}

t_begin "head range matches" && {
	sha1="$(curl -sSfv 2>$err $range_head $url | rsha1)"
	check_content_range
	test x"$sha1_head" = x"$sha1"
}

t_begin "tail range matches" && {
	sha1="$(curl -sSfv 2>$err $range_tail $url | rsha1)"
	check_content_range
	test x"$sha1_tail" = x"$sha1"
}

t_begin "mid range matches" && {
	sha1="$(curl -sSfv 2>$err $range_mid $url | rsha1)"
	check_content_range
	test x"$sha1_mid" = x"$sha1"
}

t_begin "shutdown server" && {
	kill -QUIT $rainbows_pid
}

t_begin "check stderr" && check_stderr

t_done
