/*
 * Copyright (c) 2016-2017 SEL
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 * 
 */
module sel.network.socket;

import std.conv : to;
import std.datetime : dur;
import std.socket;
import std.string;

import sel.constants;
import sel.util.log;

template BlockingSocket(T : Socket) {

	class BlockingSocket : T {

		public this(string ip, ushort port, int backlog=8, bool ipv4mapped=true) {
			this(parseAddress(ip, port), backlog, ipv4mapped);
		}

		public this(Address address, int backlog=8, bool ipv4mapped=true) {
			AddressFamily family = address.addressFamily;
			super(family == AddressFamily.INET6 && ipv4mapped ? (AddressFamily.INET6 | AddressFamily.INET) : family);
			if(family == AddressFamily.INET6) this.setOption(SocketOptionLevel.IPV6, SocketOption.IPV6_V6ONLY, !ipv4mapped);
			this.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
			this.bind(address);
			static if(!is(T == UdpSocket)) this.listen(backlog);
			this.blocking = true;
		}

	}

}

version(Posix) {

	class UnixSocket : Socket {

		public this(AddressFamily family=AddressFamily.UNIX) {
			super(family, SocketType.STREAM, cast(ProtocolType)0);
		}

	}

}

public T socketFromAddress(T : Socket)(string address, int backlog) {
	string[] spl = address.split(":");
	if(spl.length < 2) throw new AddressException("Wrong address format");
	ushort port = to!ushort(spl[$-1]);
	if(spl.length == 2 && spl[0] == "*") {
		return new T("::", port, backlog, true);
	} else {
		return new T(getAddress(spl[0..$-1].join(":"), port)[0], backlog, false);
	}
}