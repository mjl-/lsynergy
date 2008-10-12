implement Synergy;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "lists.m";
	lists: Lists;
include "synergy.m";


init()
{
	sys = load Sys Sys->PATH;
	lists = load Lists Lists->PATH;
}


tag2info := array[] of {
tagof Msg.Thello =>	("Thello",	4, "Synergy"),
tagof Msg.Rhello =>	("Rhello",	4, "Synergy"),	# xxx + string
tagof Msg.Noop =>		("Noop",	0, "CNOP"),
tagof Msg.Close =>	("Close",	0, "CBYE"),
tagof Msg.Enter =>	("Enter",	10, "CINN"),
tagof Msg.Leave =>	("Leave",	0, "COUT"),
tagof Msg.Grabclipboard =>	("Grabclipboard",	5, "CCLP"),
tagof Msg.Screensaver =>	("Screensaver",	1, "CSEC"),
tagof Msg.Resetoptions =>	("Resetoptions",	0, "CROP"),
tagof Msg.Infoack =>	("Infoack",	0, "CIAK"),
tagof Msg.Keepalive =>	("Keepalive",	0, "CALV"),
tagof Msg.Keydown =>	("Keydown",	6, "DKDN"),
tagof Msg.Keydown_10 =>	("Keydown_10",	4, "DKDN"),
tagof Msg.Keyrepeat =>	("Keyrepeat",	8, "DKRP"),
tagof Msg.Keyrepeat_10 =>	("Keyrepeat_10",	6, "DKRP"),
tagof Msg.Keyup =>	("Keyup",	6, "DKUP"),
tagof Msg.Keyup_10 =>	("Keyup_10",	4, "DKUP"),
tagof Msg.Mousedown =>	("Mousedown",	1, "DMDN"),
tagof Msg.Mouseup =>	("Mouseup",	1, "DMUP"),
tagof Msg.Mousemove =>	("Mousemove",	4, "DMMV"),
tagof Msg.Mouserelmove =>	("Mouserelmove",	4, "DMRM"),
tagof Msg.Mousewheel =>	("Mousewheel",	4, "DMWM"),
tagof Msg.Mousewheel_10 =>	("Mousewheel_10",	2, "DMWM"),
tagof Msg.Clipboard =>	("Clipboard",	0, "DCLP"),	# variable!
tagof Msg.Info =>		("Info",	14, "DINF"),
tagof Msg.Setoptions =>	("Setoptions",	4, "DSOP"),
tagof Msg.Getinfo =>	("Getinfo",	0, "QINF"),
tagof Msg.Incompatible =>	("Incompatible",	4, "EICV"),
tagof Msg.Busy =>		("Busy",	0, "EBSY"),
tagof Msg.Unknown =>	("Unknown",	0, "EUNK"),
tagof Msg.Bad =>		("Bad",		0, "EBAD"),
};

proto2tag := array[] of {
#	("Synergy",	tagof Thello),
#	("Synergy",	tagof Rhello),
	("CNOP",	tagof Msg.Noop),
	("CBYE",	tagof Msg.Close),
	("CINN",	tagof Msg.Enter),
	("COUT",	tagof Msg.Leave),
	("CCLP",	tagof Msg.Grabclipboard),
	("CSEC",	tagof Msg.Screensaver),
	("CROP",	tagof Msg.Resetoptions),
	("CIAK",	tagof Msg.Infoack),
	("CALV",	tagof Msg.Keepalive),
	("DKDN",	tagof Msg.Keydown),
#	("DKDN",	tagof Msg.Keydown_10),
	("DKRP",	tagof Msg.Keyrepeat),
#	("DKRP",	tagof Msg.Keyrepeat_10),
	("DKUP",	tagof Msg.Keyup),
#	("DKUP",	tagof Msg.Keyup_10),
	("DMDN",	tagof Msg.Mousedown),
	("DMUP",	tagof Msg.Mouseup),
	("DMMV",	tagof Msg.Mousemove),
	("DMRM",	tagof Msg.Mouserelmove),
	("DMWM",	tagof Msg.Mousewheel),
#	("DMWM",	tagof Msg.Mousewheel_10),
	("DCLP",	tagof Msg.Clipboard),
	("DINF",	tagof Msg.Info),
	("DSOP",	tagof Msg.Setoptions),
	("QINF",	tagof Msg.Getinfo),
	("EICV",	tagof Msg.Incompatible),
	("EBSY",	tagof Msg.Busy),
	("EUNK",	tagof Msg.Unknown),
	("EBAD",	tagof Msg.Bad),
};


Msg.packedsize(mm: self ref Msg): int
{
	(nil, size, name) := tag2info[tagof mm];
	size += len name;
	pick m := mm {
	Rhello =>	size += 4+len array of byte m.name;
	Clipboard =>
		size += 1+4+4;  # id, seq, clipdatasize
		size += 4;  # nformats
		for(l := m.l; l != nil; l = tl l)
			size += 4+4+len (hd l).t1;  # type, size, data
	}
	return size;
}

Msg.pack(mm: self ref Msg, d: array of byte): string
{
	proto := array of byte tag2info[tagof mm].t2;
	i := len proto;
	d[:] = proto;

	pick m := mm {
	Thello =>
		i = p16(d, i, m.major);
		i = p16(d, i, m.minor);
	Rhello =>
		i = p16(d, i, m.major);
		i = p16(d, i, m.minor);
		i = pstr(d, i, array of byte m.name);
	Noop or Close =>
		;
	Enter =>
		i = p16(d, i, m.x);
		i = p16(d, i, m.y);
		i = p32(d, i, m.seq);
		i = p16(d, i, m.mod);
	Leave =>
		;
	Grabclipboard =>
		i = p8(d, i, m.id);
		i = p32(d, i, m.seq);
	Screensaver =>
		i = p8(d, i, m.started);
	Resetoptions or Infoack or Keepalive =>
		;
	Keydown or Keyup =>
		i = p16(d, i, m.id);
		i = p16(d, i, m.modmask);
		i = p16(d, i, m.key);
	Keydown_10 or Keyup_10 =>
		i = p16(d, i, m.id);
		i = p16(d, i, m.modmask);
	Keyrepeat =>
		i = p16(d, i, m.id);
		i = p16(d, i, m.modmask);
		i = p16(d, i, m.repeats);
		i = p16(d, i, m.key);
	Keyrepeat_10 =>
		i = p16(d, i, m.id);
		i = p16(d, i, m.modmask);
		i = p16(d, i, m.repeats);
	Mousedown or Mouseup =>
		i = p8(d, i, m.id);
	Mousemove or Mouserelmove or Mousewheel =>
		i = p16s(d, i, m.x);
		i = p16s(d, i, m.y);
	Mousewheel_10 =>
		i = p16s(d, i, m.y);
	Clipboard =>
		i = p8(d, i, m.id);
		i = p32(d, i, m.seq);
		i = p32(d, i, len d-i-4);
		i = p32(d, i, len m.l);
		for(l := m.l; l != nil; l = tl l) {
			(format, buf) := *hd l;
			i = p32(d, i, format);
			i = pstr(d, i, buf);
		}
	Info =>
		i = p16(d, i, m.topx);
		i = p16(d, i, m.topy);
		i = p16(d, i, m.width);
		i = p16(d, i, m.height);
		i = p16(d, i, m.warpsize);
		i = p16(d, i, m.x);
		i = p16(d, i, m.y);
	Setoptions =>
		i = p32(d, i, m.options);
	Getinfo =>
		;
	Incompatible =>
		i = p16(d, i, m.major);
		i = p16(d, i, m.minor);
	Busy or Unknown or Bad =>
		;
	}
	if(i != len d)
		return sprint("bad Msg.pack: length buffer is %d, packed %d", len d, i);
	return nil;
}

findtag(proto: string): int
{
	for(i := 0; i < len proto2tag; i++)
		if(proto2tag[i].t0 == proto)
			return proto2tag[i].t1;
	return -1;
}

Msg.unpack(d: array of byte): (ref Msg, string)
{
	if(len d < 4)
		return (nil, "message too short");
	proto := string d[:4];
	tag := findtag(proto);
	slen := len array of byte "Synergy";
	if(tag == -1 && len d >= slen && string d[:slen] == "Synergy")
		tag = tagof Msg.Thello;
	if(tag == -1)
		return (nil, sprint("unknown type: %q", proto));

	(nil, size, name) := tag2info[tag];
	size += len array of byte name;
	if(tag == tagof Msg.Thello && len d > size) {
		size = len d;
		tag = tagof Msg.Rhello;
	}
	if(tag == tagof Msg.Clipboard && len d > size)
		size = len d;
	# xxx handle the *_10 types

	if(size != len d)
		return (nil, sprint("bad length, tag %d, need %d, have %d", tag, size, len d));

	m: ref Msg;
	i := len array of byte name;
	case tag {
	tagof Msg.Thello =>
		major, minor: int;
		(major, i) = g16(d, i);
		(minor, i) = g16(d, i);
		m = ref Msg.Thello(major, minor);
	tagof Msg.Rhello =>
		major, minor: int;
		name: array of byte;
		(major, i) = g16(d, i);
		(minor, i) = g16(d, i);
		(name, i) = gstr(d, i);
		if(name == nil)
			return (nil, "bad string in Msg.Rhello");
		m = ref Msg.Rhello(major, minor, string name);
	tagof Msg.Noop =>
		m = ref Msg.Noop();
	tagof Msg.Close =>
		m = ref Msg.Close();
	tagof Msg.Enter =>
		x, y, seq, mod: int;
		(x, i) = g16(d, i);
		(y, i) = g16(d, i);
		(seq, i) = g32(d, i);
		(mod, i) = g16(d, i);
		m = ref Msg.Enter(x, y, seq, mod);
	tagof Msg.Leave =>
		m = ref Msg.Leave();;
	tagof Msg.Grabclipboard =>
		id, seq: int;
		(id, i) = g8(d, i);
		(seq, i) = g32(d, i);
		m = ref Msg.Grabclipboard(id, seq);
	tagof Msg.Screensaver =>
		started: int;
		(started, i) = g8(d, i);
		m = ref Msg.Screensaver(started);
	tagof Msg.Resetoptions =>
		m = ref Msg.Resetoptions();
	tagof Msg.Infoack =>
		m = ref Msg.Infoack();
	tagof Msg.Keepalive =>
		m = ref Msg.Keepalive();
	tagof Msg.Keydown or tagof Msg.Keyup =>
		id, modmask, key: int;
		(id, i) = g16(d, i);
		(modmask, i) = g16(d, i);
		(key, i) = g16(d, i);
		if(tag == tagof Msg.Keydown)
			m = ref Msg.Keydown(id, modmask, key);
		else
			m = ref Msg.Keyup(id, modmask, key);
	tagof Msg.Keydown_10 or tagof Msg.Keyup_10 =>
		id, modmask: int;
		(id, i) = g16(d, i);
		(modmask, i) = g16(d, i);
		if(tag == tagof Msg.Keydown)
			m = ref Msg.Keydown_10(id, modmask);
		else
			m = ref Msg.Keyup_10(id, modmask);
	tagof Msg.Keyrepeat =>
		id, modmask, repeats, key: int;
		(id, i) = g16(d, i);
		(modmask, i) = g16(d, i);
		(repeats, i) = g16(d, i);
		(key, i) = g16(d, i);
		m = ref Msg.Keyrepeat(id, modmask, repeats, key);
	tagof Msg.Keyrepeat_10 =>
		id, modmask, repeats: int;
		(id, i) = g16(d, i);
		(modmask, i) = g16(d, i);
		(repeats, i) = g16(d, i);
		m = ref Msg.Keyrepeat_10(id, modmask, repeats);
	tagof Msg.Mousedown or tagof Msg.Mouseup =>
		id: int;
		(id, i) = g8(d, i);
		if(tag == tagof Msg.Mousedown)
			m = ref Msg.Mousedown(id);
		else
			m = ref Msg.Mouseup(id);
	tagof Msg.Mousemove or tagof Msg.Mouserelmove or tagof Msg.Mousewheel =>
		x, y: int;
		(x, i) = g16s(d, i);
		(y, i) = g16s(d, i);
		case tag {
		tagof Msg.Mousemove =>
			m = ref Msg.Mousemove(x, y);
		tagof Msg.Mouserelmove =>
			m = ref Msg.Mouserelmove(x, y);
		tagof Msg.Mousewheel =>
			m = ref Msg.Mousewheel(x, y);
		}
	tagof Msg.Mousewheel_10 =>
		y: int;
		(y, i) = g16s(d, i);
		m = ref Msg.Mousewheel_10(y);
	tagof Msg.Clipboard =>
		id, seq: int;
		data: array of byte;
		if(len d < 1+4+4)
			return (nil, "short initial data for Msg.Clipboard");
		(id, i) = g8(d, i);
		(seq, i) = g32(d, i);
		(data, i) = gstr(d, i);
		if(data == nil || len data < 4)
			return (nil, "short clipboard data in Msg.Clipboard");
		(nclip, j) := g32(data, 0);
		l: list of ref (int, array of byte);
		while(nclip-- > 0) {
			if(len data < 8)
				return (nil, "short clipboard format for Msg.Clipboard");
			format: int;
			buf: array of byte;
			(format, j) = g32(data, j);
			(buf, j) = gstr(data, j);
			l = ref(format, buf)::l;
		}
		m = ref Msg.Clipboard(id, seq, lists->reverse(l));
	tagof Msg.Info =>
		topx, topy, width, height, warpsize, x, y: int;
		(topx, i) = g16(d, i);
		(topy, i) = g16(d, i);
		(width, i) = g16(d, i);
		(height, i) = g16(d, i);
		(warpsize, i) = g16(d, i);
		(x, i) = g16(d, i);
		(y, i) = g16(d, i);
		m = ref Msg.Info(topx, topy, width, height, warpsize, x, y);
	tagof Msg.Setoptions =>
		# xxx
		options: int;
		(options, i) = g32(d, i);
		m = ref Msg.Setoptions(options);
	tagof Msg.Getinfo =>
		m = ref Msg.Getinfo();
	tagof Msg.Incompatible =>
		major, minor: int;
		(major, i) = g16(d, i);
		(minor, i) = g16(d, i);
		m = ref Msg.Incompatible(major, minor);
	tagof Msg.Busy =>
		m = ref Msg.Busy();
	tagof Msg.Unknown =>
		m = ref Msg.Unknown();
	tagof Msg.Bad =>
		m = ref Msg.Bad();
	}
	if(m == nil)
		raise "missing case in Msg.unpack";
	if(i != len d)
		return (nil, sprint("bad Msg.unpack: length buffer is %d, packed %d", len d, i));
	return (m, nil);
}

Msg.text(mm: self ref Msg): string
{
	s: string;
	pick m := mm {
	Thello =>		s = sprint("major=%d minor=%d", m.major, m.minor);
	Rhello =>		s = sprint("major=%d minor=%d name=%q", m.major, m.minor, m.name);
	Noop or Close =>	;
	Enter =>		s = sprint("x=%d y=%d seq=%d mod=0x%x", m.x, m.y, m.seq, m.mod);
	Leave =>		;
	Grabclipboard =>	s = sprint("id=%d seq=%d", m.id, m.seq);
	Screensaver =>		s = sprint("started=%d", m.started);
	Resetoptions or Infoack or Keepalive =>
				;
	Keydown or Keyup =>	s = sprint("id=%d modmask=%d key=%d", m.id, m.modmask, m.key);
	Keydown_10 or Keyup_10 =>	s = sprint("id=%d modmask=%d", m.id, m.modmask);
	Keyrepeat =>		s = sprint("id=%d modmask=%d repeats=%d key=%d", m.id, m.modmask, m.repeats, m.key);
	Keyrepeat_10 =>		s = sprint("id=%d modmask=%d repeats=%d", m.id, m.modmask, m.repeats);
	Mousedown or Mouseup =>	s = sprint("id=%d", m.id);
	Mousemove or Mouserelmove or Mousewheel =>
				s = sprint("x=%d y=%d", m.x, m.y);
	Mousewheel_10 =>	s = sprint("y=%d", m.y);
	Clipboard =>
		s = sprint("id=%d seq=%d nclips=%d", m.id, m.seq, len m.l);
		for(l := m.l; l != nil; l = tl l) {
			s += sprint(", fmt=%d buf=%q", (hd l).t0, string (hd l).t1);
		}
	Info =>			s = sprint("topx=%d topy=%d width=%d heigh=%d warpsize=%d x=%d y=%d", m.topx, m.topy, m.width, m.height, m.warpsize, m.x, m.y);
	Setoptions =>		s = sprint("options=%d", m.options);
	Getinfo =>		;
	Incompatible =>		s = sprint("major=%d minor=%d", m.major, m.minor);
	Busy or Unknown or Bad =>
				;
	* =>
		raise "missing case in Msg.text";
	}

	return tag2info[tagof mm].t0+"("+s+")";
}


readmsg(fd: ref Sys->FD): (array of byte, string)
{
	n := sys->readn(fd, buf := array[4] of byte, len buf);
	if(n < 0)
		return (nil, sprint("reading length: %r"));
	if(n != 4)
		return (nil, "short read while reading length");

	(size, nil) := g32(buf, 0);
	if(size < 0)
		return (nil, "bad size");
	n = sys->readn(fd, buf = array[size] of byte, len buf);
	if(n < 0)
		return (nil, sprint("reading message (%d bytes): %r", size));
	if(n != size)
		return (nil, sprint("short read on message (want %d, have %d)", size, n));

	return (buf, nil);
}

writemsg(fd: ref Sys->FD, m: ref Msg): string
{
	size := m.packedsize();
	buf := array[4+size] of byte;
	err := m.pack(buf[4:]);
	if(err != nil)
		return err;

	p32(buf, 0, size);
	n := sys->write(fd, buf, len buf);
	if(n != len buf)
		return sprint("%r");
	return nil;
}


Session.new(fd: ref Sys->FD, name: string): (ref Session, string)
{
	(buf, err) := readmsg(fd);
	if(err != nil)
		return (nil, err);
	m: ref Msg;
	(m, err) = Msg.unpack(buf);
	if(err != nil)
		return (nil, err);

	major, minor: int;
	pick mm := m {
	Thello =>
		major = mm.major;
		minor = mm.minor;
	* =>
		return (nil, "bad message from server, expected handshake");
	}

	err = writemsg(fd, ref Msg.Rhello(MAJOR, MINOR, name));
	if(err != nil)
		return (nil, "writing handshake message: "+err);

	return (ref Session(fd, major, minor), nil);
}

Session.readmsg(s: self ref Session): (ref Msg, string)
{
	(buf, err) := readmsg(s.fd);
	if(err != nil)
		return (nil, err);
	return Msg.unpack(buf);
}

Session.writemsg(s: self ref Session, m: ref Msg): string
{
	return writemsg(s.fd, m);
}


p8(d: array of byte, i: int, v: int): int
{
	d[i++] = byte (v>>0);
	return i;
}

p16(d: array of byte, i: int, v: int): int
{
	d[i++] = byte (v>>8);
	d[i++] = byte (v>>0);
	return i;
}

p16s(d: array of byte, i: int, v: int): int
{
	return p16(d, i, v);
}

p32(d: array of byte, i: int, v: int): int
{
	d[i++] = byte (v>>24);
	d[i++] = byte (v>>16);
	d[i++] = byte (v>>8);
	d[i++] = byte (v>>0);
	return i;
}

pstr(d: array of byte, i: int, data: array of byte): int
{
	i = p32(d, i, len data);
	d[i:] = data;
	i += len data;
	return i;
}

g8(d: array of byte, i: int): (int, int)
{
	v := 0;
	v |= int (d[i++]<<0);
	return (v, i);
}

g16(d: array of byte, i: int): (int, int)
{
	v := 0;
	v |= int d[i++]<<8;
	v |= int d[i++]<<0;
	return (v, i);
}


g16s(d: array of byte, i: int): (int, int)
{
	v := 0;
	v |= int d[i++]<<24;
	v |= int d[i++]<<16;
	return (v>>16, i);
}

g32(d: array of byte, i: int): (int, int)
{
	v := 0;
	v |= int d[i++]<<24;
	v |= int d[i++]<<16;
	v |= int d[i++]<<8;
	v |= int d[i++]<<0;
	return (v, i);
}

gstr(d: array of byte, i: int): (array of byte, int)
{
	n: int;
	(n, i) = g32(d, i);
	if(len d-i < n)
		return (nil, i);
	data := d[i:i+n];
	return (data, i+n);
}
