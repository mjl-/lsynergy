implement Synerc;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
include "synergy.m";
	syn: Synergy;
	Session, Msg: import syn;


dflag: int;
addr := "net!$synergy!24800";
name: string;
session: ref Session;

Synerc: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

kbpath: con "/dev/kbin";
mousepath: con "/dev/mousein";
kbfd: ref Sys->FD;
mousefd: ref Sys->FD;
timefd: ref Sys->FD;
reswidth, resheight: int;
Snarfmax:	con 32*1024;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	syn = load Synergy Synergy->PATH;
	syn->init();

	# for testing
	addr = "net!localhost!24800";
	name = sysname();

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] [-a addr] [-n name] width height");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'n' =>	name = arg->earg();
		'd' =>	dflag++;
		* =>	sys->fprint(sys->fildes(2), "bad option\n");
			arg->usage();
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();
	reswidth = int hd args;
	resheight = int hd tl args;

	timefd = sys->open("/dev/time", Sys->OREAD);
	if(timefd == nil)
		fail(sprint("open /dev/time: %r"));

	kbfd = sys->open(kbpath, Sys->OWRITE);
	if(kbfd == nil)
		fail(sprint("open %q: %r", kbpath));
	mousefd = sys->open(mousepath, Sys->OWRITE);
	if(mousefd == nil)
		fail(sprint("open %q: %r", mousepath));

	(ok, conn) := sys->dial(addr, nil);
	if(ok < 0)
		fail(sprint("dial %s: %r", addr));
	fd := conn.dfd;
	say("have connection");

	err: string;
	(session, err) = Session.new(fd, name);
	if(err != nil)
		fail("handshaking: "+err);
	say("have handshake");

	spawn synergyserve();
}

mousex := mousey := mousebtn := 0;
mousewrite(dx, dy, btn: int)
{
	mousebtn = btn;
	mousex += dx;
	mousey += dy;
	if(sys->fprint(mousefd, "m %11d %11d %11d %11bd", dx, dy, mousebtn, msec()) < 0)
		say(sprint("mousewrite: %r"));
	say(sprint("wrote mouse: m %11d %11d %11d %11bd", dx, dy, mousebtn, msec()));
}

msec(): big
{
	buf := array[32] of byte;
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		n = 0;
	return big string buf[:n];
}

synergyserve()
{
	seq := 0;

	for(;;) {
		(mm, err) := session.readmsg();
		if(err != nil)
			fail("reading message: "+err);
		say(sprint("have message: %s", mm.text()));

		resp: ref Msg;
		pick m := mm {
		Busy =>
			fail("already connected");
		Unknown =>
			fail("unknown something");
		Bad =>
			fail("something bad");
		Close =>
			fail("we need to close");
		Keepalive =>
			resp = ref Msg.Keepalive();
		Getinfo =>
			resp = ref Msg.Info(0, 0, reswidth, resheight, 0, 0, 0); # xxx need to get screensize?
		Mousedown =>
			mousewrite(0, 0, mousebtn|1<<(m.id-1));
		Mouseup =>
			mousewrite(0, 0, mousebtn&~(1<<(m.id-1)));
		Mousemove =>
			mousewrite(m.x-mousex, m.y-mousey, mousebtn);
		Mouserelmove =>
			mousewrite(m.x, m.y, mousebtn);
		# Mousewheel_10 ?
		Mousewheel =>
			btn := 1<<3;
			if(m.y < 0)
				btn = 1<<4;
			mousewrite(0, 0, mousebtn|btn);
			mousewrite(0, 0, mousebtn&~btn);
		Keydown =>
			# id & modmask are processed.  key is raw scancode (but not directly from keyboard)
			writekey(m.key, 0);
		Keyup =>
			writekey(m.key, 1);
		Keyrepeat =>
			writekey(m.key, 0);
		# Key(up|down|repeat)_10 ?
		Enter =>
			# mod ?
			seq = m.seq;
			mousewrite(-reswidth, -resheight, 0);
			mousewrite(m.x, m.y, 0);
			mousex = m.x;
			mousey = m.y;
			say("now have focus");
			# xxx we might want to grab the clipboard, and on leave, reread it & send new version if changed
		Leave =>
			say("lost focus");
			if(mousebtn != 0)
				mousewrite(0, 0, 0);
			buf: array of byte;
			(buf, err) = readsnarf();
			if(err != nil) {
				warn("reading snarf: "+err);
			} else {
				m1 := ref Msg.Grabclipboard(1, seq);
				m2 := ref Msg.Clipboard (1, seq, ref (Synergy->Ttext, buf)::nil);
				err = session.writemsg(m1);
				if(err == nil)
					session.writemsg(m2);
				if(err != nil)
					fail(err);
			}
		Grabclipboard =>
			# id, seq ?
			say(sprint("other machine grabs clipboard?"));
		Clipboard =>
			# id, seq ?
			havetext := 0;
			for(l := m.l; !havetext && l != nil; l = tl l) {
				(format, buf) := *hd l;
				case format {
				Synergy->Ttext or Synergy->Thtml =>
					err = writesnarf(buf);
					if(err != nil)
						warn("writing snarf buffer: "+err);
				* =>
					say(sprint("ignoring clipboard buffer, unsupported type %d", format));
				}
				if(format == Synergy->Ttext)
					havetext = 1;
			}
		Screensaver =>
			# xxx perhaps only use this when we have focus?  or just ignore altogether
			if(m.started) {
				fd := sys->open("/dev/vgactl", Sys->OWRITE);
				if(fd == nil || sys->fprint(fd, "blank") < 0)
					warn(sprint("vgactl blank: %r"));
			}
		* =>
			say("message not handled");
		}
		if(resp != nil) {
			say(sprint("responding with: %s", resp.text()));
			err = session.writemsg(resp);
			if(err != nil)
				fail(err);
		}
	}
}

writesnarf(buf: array of byte): string
{
	fd := sys->open("/dev/snarf", Sys->OWRITE);
	if(fd == nil)
		return sprint("open: %r");
	n := sys->write(fd, buf, len buf);
	if(n != len buf)
		return sprint("write: %r");
	return nil;
}

readsnarf(): (array of byte, string)
{
	fd := sys->open("/dev/snarf", Sys->OREAD);
	if(fd == nil)
		return (nil, sprint("open: %r"));
	buf := array[Snarfmax] of byte;
	n := sys->readn(fd, buf, len buf);
	if(n < 0)
		return (nil, sprint("read: %r"));
	return (buf[:n], nil);
}

# this currently maps from xorg key codes.  i don't know what those are supposed to mean.  a windows synergy server probably generates different key codes...
# the codes are mapped to scancodes from set 1 as used by plan 9
writekey(k, up: int): string
{
	buf: array of byte;
	if(k < 16r59) {
		# single byte command
		k -= 8;
		if(up)
			k |= 16r80;
		buf = array[] of {byte k};
	} else {
		# two byte "escaped" command
		k -= 26;
		if(up)
			k |= 16r80;
		buf = array[] of {byte 16rE0, byte k};
	}

	if(sys->write(kbfd, buf, len buf) != len buf)
		return sprint("writing key: %r");
	return nil;
}

sysname(): string
{
	fd := sys->open("/dev/sysname", Sys->OREAD);
	if(fd != nil && (n := sys->read(fd, buf := array[256] of byte, len buf)) > 0)
		return string buf[:n];
	return "none";
}

max(a, b: int): int
{
	if(a < b)
		return b;
	return a;
}

min(a, b: int): int
{
	if(a < b)
		return a;
	return b;
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
}

say(s: string)
{
	if(dflag)
		warn(s);
}

fail(s: string)
{
	warn(s);
	raise "fail:"+s;
}
