﻿/*
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
module sel.plugin.plugin;

import std.conv : to;
import std.traits : isAbstractClass, getUDAs, hasUDA;

import common.sel;

import sel.server : server;

/**
 * Informations about a plugin and registration-related
 * utilities.
 */
struct Plugin {

	public string n_namespace, n_name, n_author, n_version;
	public bool n_api;
	public bool hasMain;

	public void delegate()[] onstart, onreload, onstop;

	/**
	 * Gets the plugin's namespace that corresponds to the plugin's
	 * source code in plugins/<namespace> and the plugin's resources
	 * in resources/<namespace>.
	 */
	public pure nothrow @property @safe @nogc string namespace() {
		return this.n_namespace;
	}

	/**
	 * Gets the plugin's name as indicated in the plugin's
	 * package.json file.
	 */
	public pure nothrow @property @safe @nogc string name() {
		return this.n_name;
	}

	/**
	 * Gets the plugin's author as indicated in the plugin's
	 * package.json file.
	 */
	public pure nothrow @property @safe @nogc string author() {
		return this.n_author;
	}

	/**
	 * Gets the plugin's version as indicated in the plugin's
	 * package.json file.
	 * This should be in major.minor[.revision] [alpha|beta] format.
	 */
	public pure nothrow @property @safe @nogc string vers() {
		return this.n_version;
	}

	/**
	 * Indicates whether or not the plugin has APIs.
	 * The plugin's APIs are always in the api.d file in
	 * the plugin's directory.
	 * Example:
	 * ---
	 * static if(__traits(compile, { import example.api; })) {
	 *    assert(server.plugins.filter!(a => a.namespace == "example")[0].api);
	 * }
	 * ---
	 */
	public pure nothrow @property @safe @nogc bool api() {
		return this.n_api;
	}

	public static Plugin create(T)(Plugin info) if(is(T == class) && !isAbstractClass!T || is(T == struct)) {
		static if(!is(T == Object)) {
			static if(is(T == class)) {
				T main = new T();
			} else {
				T main = T();
			}
			info.hasMain = true;
			foreach(t ; __traits(allMembers, T)) {
				static if(is(typeof(__traits(getMember, T, t)) == function)) {
					mixin("alias func = T." ~ t ~ ";");
					mixin("auto del = &main." ~ t ~ ";");
					// start/stop
					static if(hasUDA!(func, start)) {
						info.onstart ~= del;
					}
					static if(hasUDA!(func, reload)) {
						info.onreload ~= del;
					}
					static if(hasUDA!(func, stop)) {
						info.onstop ~= del;
					}
					// events
					static if(hasUDA!(func, event)) {
						registerEvent!(false, hasUDA!(func, cancel))(del);
					}
					static if(hasUDA!(func, global)) {
						registerEvent!(true, hasUDA!(func, cancel))(del);
					}
					// commands
					static if(hasUDA!(func, command)) {
						static if(hasUDA!(func, description)) {
							enum d = getUDAs!(func, description)[0];
						} else {
							enum d = "";
						}
						static if(hasUDA!(func, aliases)) {
							enum a = getUDAs!(func, aliases)[0];
						} else {
							enum a = new string[0];
						}
						static if(hasUDA!(func, params)) {
							enum p = getUDAs!(func, params);
						} else {
							enum p = new string[0];
						}
						server.registerCommand!(func)(del, getUDAs!(func, command)[0], d, a, p);
					}
					// tasks
					static if(hasUDA!(func, task)) {
						server.addTask(del, getUDAs!(func, task)[0]);
					}
				}
			}
		} else {
			info.hasMain = false;
		}
		return info;
	}

	private static void registerEvent(bool isGlobal, bool isCancelled, T)(void delegate(T) event) {
		static if(isCancelled) {
			event = (T e){ e.cancel(); };
		}
		static if(isGlobal) {
			server.globalListener.addEventListener(event);
		} else {
			server.addEventListener(event);
		}
	}

}

enum start;
enum reload;
enum stop;

// attributes for events
enum event;
enum global;
enum inherit;
enum cancel;

struct command {

	string command;

	alias command this;

}

struct description {

	string description;

	alias description this;

}

struct aliases {

	string[] aliases;

	public this(string[] aliases...) {
		this.aliases = aliases;
	}

	alias aliases this;

}

struct params {

	string[] params;

	public this(string[] params...) {
		this.params = params;
	}

	alias params this;

}

struct task {

	tick_t interval=1;

	alias interval this;

}

alias arguments = immutable(string)[];

/** Generic plugin exception */
class PluginException : Exception {

	public @safe @nogc this(string message, string file=__FILE__, size_t line=__LINE__) {
		super(message, file, line);
	}

}
