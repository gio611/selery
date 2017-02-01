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
module sel.world.file;

import std.system : Endian, endian;

import sel.world.generator;
import sel.world.io;
import sel.world.world : World;

class RegionWorld(T) : World {

	protected ubyte[][int][int] cached_regions;

	public this(string name, uint seed, Generator generator=null) {
		super(name, generator, seed);
	}

}

alias SelWorld(Endian endianness) = RegionWorld!(Sel!endianness);

alias DefaultSelWorld = SelWorld!endian;
