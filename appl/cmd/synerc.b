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
addr := "net!$synergy!synergy";
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
	arg->setusage(arg->progname()+" [-d] [-a addr] [-n name]");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'n' =>	name = arg->earg();
		'd' =>	dflag++;
		* =>	sys->fprint(sys->fildes(2), "bad option\n");
			arg->usage();
		}
	args = arg->argv();
	if(len args != 0)
		arg->usage();

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
mousewrite()
{
	if(sys->fprint(mousefd, "m %11d %11d %11d %11bd", mousex, mousey, mousebtn, msec()) < 0)
		say(sprint("mousewrite: %r"));
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
			resp = ref Msg.Info(0, 0, 800, 600, 0, 0, 0); # xxx need to get screensize?
		Mousedown =>
			say(sprint("mousedown id %d", m.id));
			mousebtn |= 1<<(m.id-1);
			mousewrite();
		Mouseup =>
			say(sprint("mouseup, id %d", m.id));
			mousebtn &= ~(1<<(m.id-1));
			mousewrite();
		Mousemove =>
			mousex = m.x;
			mousey = m.y;
			mousewrite();
		Mouserelmove =>
			mousex += m.x;
			mousey += m.y;
			mousewrite();
		# Mousewheel_10 ?
		Mousewheel =>
			btn := 1<<3;
			if(m.y&16r8000)  # 16 bit, sign.  i.e. <0
				btn = 1<<4;
			mousebtn |= btn;
			mousewrite();
			mousebtn &= ~btn;
			mousewrite();

		Keydown =>
			# mod 2 == ctrl?
			# alt, shift, etc?
			# id, modmask, button
			;
		Keyup =>
			# see lib/synergy/KeyTypes.h for the types
			id := m.id;
			case id {
			16rEF0d =>	id = '\n';
			#16rEF08 =>	id = '\b';
			16rEF09 =>	id = '\t';
			16rEF0A =>	id &= 16rFF;
			}
			buf := array[2] of {byte (id>>8), byte id};
			n := sys->write(kbfd, buf, len buf);
			if(n != len buf)
				say(sprint("writing to keyboard: %r"));
			say("wrote");
		# Keyrepeat
		# Key(up|down|repeat)_10
		Enter =>
			# seq, mod ?
			mousex = m.x;
			mousey = m.y;
			mousewrite();
			say("now have focus");
		Leave =>
			say("lost focus");
			mousebtn = 0;
			mousewrite();

		# Grabclipboard
		# Clipboard;  id, seq;  data
		}
		if(resp != nil) {
			say(sprint("responding with: %s", resp.text()));
			err = session.writemsg(resp);
			if(err != nil)
				fail(err);
		}
	}
}

sysname(): string
{
	fd := sys->open("/dev/sysname", Sys->OREAD);
	if(fd != nil && (n := sys->read(fd, buf := array[256] of byte, len buf)) > 0)
		return string buf[:n];
	return "none";
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
