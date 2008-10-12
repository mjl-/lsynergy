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
			say(sprint("mousedown id %d", m.id));
			mousewrite(0, 0, mousebtn|1<<(m.id-1));
		Mouseup =>
			say(sprint("mouseup, id %d", m.id));
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
			# mod 2 == ctrl
			# alt, shift, etc?
			# id, modmask, key
			writekey(m.key, 0);
		Keyup =>
			writekey(m.key, 1);
		# Keyrepeat
		# Key(up|down|repeat)_10
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

Yesc, Ybackspace, Ylctrl, Ylshift, Yrshift, Ylalt, Ycapslock, Yfn: con iota+255;
Ynumlock, Yscrolllock, Yaltsysreq, Yibmfn, Yxxx, Yhome, Yup, Ypgup, Yleft, Yright, Yend, Ydown, Ypgdn, Yins, Ydel: con iota+1+Yfn+12;


map := array[] of {
0, Yesc, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', Ybackspace,
'\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']',
'\n',
Ylctrl,
'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'',
'`',
Ylshift,
'\\',
'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', Yrshift,
'*',
Ylalt, ' ',
Ycapslock,
Yfn|1, Yfn|2, Yfn|3, Yfn|4, Yfn|5, Yfn|6, Yfn|7, Yfn|8, Yfn|9, Yfn|10,
Ynumlock,
Yscrolllock,
'7', '8', '9',
'-',
'4', '5', '6', '+',
'1', '2', '3',
'0', '.',
Yaltsysreq,
Yibmfn,
Yxxx,
Yfn|11, Yfn|12,
};

shiftmap := array[] of {
0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0,
0, 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}',
0,
0,
'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"',
'~',
0,
'|',
'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,
0,
0, 0,
0, # caps
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, # f1 to f10
0, # numlock
0, # scroll lock
Yhome, Yup, Ypgup,
0, # keypad -
Yleft, 0, Yright, 0,
Yend, Ydown, Ypgdn,
Yins, Ydel,
};

writekey(k: int, up: int): string
{
	case k {
	16rEF08 =>	k = Ybackspace;
	16rEF09 =>	k = '\t';
	16rEF0A =>	k = '\n';
	16rEF0D =>	k = '\n';
	16rEF1B =>	k = Yesc;
	16rEF50 =>	k = Yhome;
	16rEF51 =>	k = Yleft;
	16rEF52 =>	k = Yup;
	16rEF53 =>	k = Yright;
	16rEF54 =>	k = Ydown;
	16rEF55 =>	k = Ypgup;
	16rEF56 =>	k = Ypgdn;
	16rEF57 =>	k = Yend;
	16rEF63 =>	k = Yins;
	16rEFFF =>	k = Ydel;
	0 to 16r7f =>	# normal ascii
		;
	* =>
		if(up)
			return nil;
		# unicode?  send as alt X dddd ?
		# write it, and done
		# alt down, shift down, x, shift up, alt up, d1, d2, d3, d4
		; # xxx
	}

	# try to find scancode.  if found write & done.  otherwise just warn

	# most are single-byte
	# e0 is followed by 1 byte
	# e1 is followed by 2 bytes
	# some keys generate down+up at once?

	#if(up)
	#	c |= 16r80;
	#kb := array[1] of byte;
	#kb[0] = byte c;
	#if(sys->write(kbfd, kb, len kb) != len kb)
	#	return sprint("writing key: %r");
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
