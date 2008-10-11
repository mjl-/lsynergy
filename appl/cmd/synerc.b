implement Synerc;

include "sys.m";
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "styx.m";
include "styxservers.m";
include "synergy.m";

sys: Sys;
styx: Styx;
styxservers: Styxservers;
nametree: Nametree;
syn: Synergy;

print, sprint, fprint, fildes: import sys;
Tmsg, Rmsg: import Styx;
Styxserver, Fid, Navigator: import styxservers;
Session, Msg: import syn;
Tree: import nametree;

dflag: int;
addr := "net!$synergy!synergy";
name: string;
session: ref Session;

Synerc: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

#Queue: adt {
#	fids:	array of (int, (list of ref Tmsg.Read, list of array of byte));
#
#	new:	fn(): Queue;
#	newfid:	fn(q: self Queue, fid: int);
#	addread:	fn(q: self Queue, m: ref Tmsg.Read);
#	adddata:	fn(q: self Queue, d: array of byte);
#	act:	fn(q: self Queue, srv: ref Styxserver);
#};

#keyb: Queue;


keybfd: ref Sys->FD;
pointerfd: ref Sys->FD;

Qroot, Qkeyboard, Qpointer, Qsnarf: con big iota;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	syn = load Synergy Synergy->PATH;
	syn->init();

	# for testing
	addr = "net!localhost!24800";
	name = readfile("/dev/sysname");

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] [-a addr] [-n name]");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'n' =>	name = arg->earg();
		'd' =>	dflag++;
		* =>	fprint(fildes(2), "bad option\n");
			arg->usage();
		}
	args = arg->argv();
	if(len args != 0)
		arg->usage();

	keybfd = sys->open("/dev/keyboard", Sys->OWRITE);
	if(keybfd == nil)
		fail(sprint("opening keyboard for writing: %r"));
	#pointerfd = sys->open("/dev/pointer", Sys->OWRITE);
	#if(pointerfd == nil)
	#	fail(sprint("opening pointer for writing: %r"));

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

	#styxinch = chan of ref Tmsg;
	#styxoutch = chan of ref Rmsg;
	#datainch = chan of (int, array of byte);

	#spawn styxserve();
	spawn synergyserve();
}

styxserve()
{
	(tree, treeop) := nametree->start();
	tree.create(Qroot, dir(".", 8r555|Sys->DMDIR, Qroot));
	tree.create(Qroot, dir("keyboard", 8r666, Qkeyboard));
	tree.create(Qroot, dir("pointer", 8r666, Qpointer));
	tree.create(Qroot, dir("snarf", 8r666, Qsnarf));
	(tchan, srv) := Styxserver.new(sys->fildes(0), Navigator.new(treeop), Qroot);
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			say("read error: "+m.error);
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR){
				srv.default(m);
				break;
			}

			case c.path {
			Qkeyboard =>
				# queue read
				# respond to all queued reads on keyboard
				;
			Qpointer =>
				;
			Qsnarf =>
				;
			* =>
				srv.reply(ref Rmsg.Error(m.tag, "read on unknown file"));
			}

			#m.offset
			#m.count
			#srv.reply(ref Rmsg.Read(m.tag, a[:have]));
			srv.reply(ref Rmsg.Error(m.tag, "not yet implemented"));

		Write =>
			#int fid,
			#big offset
			#data
			srv.reply(ref Rmsg.Error(m.tag, "not yet implemented"));
		* =>
			srv.default(gm);
		}
	}
	tree.quit();
}

dir(name: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = "synergy";
	d.gid = "synergy";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	return d;
}

synergyserve()
{
	for(;;) {
		(m, err) := session.readmsg();
		if(err != nil)
			fail("reading message: "+err);
		say(sprint("have message: %s", m.text()));

		resp: ref Msg;
		pick mm := m {
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
			resp = ref Msg.Info(0, 0, 800, 600, 0, 0, 0);
		Mousemove =>
			#buf := array of byte sprint("m %11d %11d %11d %11d", mm.x, mm.y, 0, 0);
			#n := sys->write(pointerfd, buf, len buf);
			#if(n != len buf)
			#	say(sprint("writing to pointer: %r"));

		Keyup =>
			# see lib/synergy/KeyTypes.h for the types
			id := mm.id;
			case id {
			16rEF0d =>	id = '\n';
			#16rEF08 =>	id = '\b';
			16rEF09 =>	id = '\t';
			16rEF0A =>	id &= 16rFF;
			}
			buf := array[2] of {byte (id>>8), byte id};
			n := sys->write(keybfd, buf, len buf);
			if(n != len buf)
				say(sprint("writing to keyboard: %r"));
			say("wrote");
		}
		if(resp != nil) {
			say(sprint("responding with: %s", resp.text()));
			err = session.writemsg(resp);
			if(err != nil)
				fail(err);
		}
	}
}

readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return "none";
	n := sys->read(fd, buf := array[256] of byte, len buf);
	if(n <= 0)
		return "none";
	return string buf[:n];
}

say(s: string)
{
	if(dflag)
		fprint(fildes(2), "%s\n", s);
}

fail(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}
