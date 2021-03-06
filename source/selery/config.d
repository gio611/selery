/*
 * Copyright (c) 2017-2018 sel-project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 */
/**
 * Copyright: Copyright (c) 2017-2018 sel-project
 * License: MIT
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/selery/source/selery/config.d, selery/config.d)
 */
module selery.config;

import std.algorithm : canFind, min;
import std.conv : to;
import std.file : exists, isFile, read, write;
import std.json : JSONValue;
import std.path : dirSeparator;
import std.random : uniform;
import std.socket : getAddress;
import std.string : indexOf, startsWith, endsWith;
import std.uuid : UUID, randomUUID;

import selery.about;
import selery.lang : LanguageManager;
import selery.plugin : Plugin;

enum Gamemode : ubyte {
	
	survival = 0, s = 0,
	creative = 1, c = 1,
	adventure = 2, a = 2,
	spectator = 3, sp = 3,
	
}

enum Difficulty : ubyte {
	
	peaceful = 0,
	easy = 1,
	normal = 2,
	hard = 3,
	
}

enum Dimension : ubyte {
	
	overworld = 0,
	nether = 1,
	end = 2,
	
}

/**
 * Configuration for the server.
 */
class Config {

	UUID uuid;

	Files files;
	LanguageManager lang;

	Hub hub;
	Node node;

	public this(UUID uuid=randomUUID()) {
		this.uuid = uuid;
	}
	
	/**
	 * Configuration for the hub.
	 */
	class Hub {

		static struct Address {

			string ip;
			ushort port;

			inout string toString() {
				return (this.ip.canFind(":") ? "[" ~ this.ip ~ "]" : this.ip) ~ ":" ~ this.port.to!string;
			}

		}

		static struct Game {
			
			bool enabled;
			string motd;
			bool onlineMode;
			Address[] addresses;
			uint[] protocols;
			
			alias enabled this;
			
		}

		bool edu;

		string displayName = "A Minecraft Server";

		Game bedrock = Game(true, "A Minecraft Server", false, [Address("0.0.0.0", 19132)], latestBedrockProtocols);
		
		Game java = Game(true, "A Minecraft Server", false, [Address("0.0.0.0", 25565)], latestJavaProtocols);
		
		bool allowVanillaPlayers = false;
		
		bool query = true;
		
		string serverIp;
		
		string favicon = "favicon.png";
		
		JSONValue social;
		
		string[] acceptedNodes;
		
		string hncomPassword;
		
		uint maxNodes = 0;
		
		ushort hncomPort = 28232;

		public this() {

			if(lang !is null) {
				this.displayName = this.java.motd = this.bedrock.motd = (){
					switch(lang.language[0..min(cast(size_t)lang.language.indexOf("_"), $)]) {
						case "es": return "Un Servidor de Minecraft";
						case "it": return "Un Server di Minecraft";
						case "pt": return "Um Servidor de Minecraft";
						default: return "A Minecraft Server";
					}
				}();
			}

			this.acceptedNodes ~= getAddress("localhost")[0].toAddrString();
		}

	}

	/**
	 * Configuration for the node.
	 */
	class Node {

		static struct Game {

			bool enabled;
			uint[] protocols;

			alias enabled this;

		}

		string name = "node";

		string password = "";

		string ip;

		ushort port = 28232;

		bool main = true;

		Game java = Game(true, latestJavaProtocols);

		Game bedrock = Game(true, latestBedrockProtocols);

		uint maxPlayers = 20;

		Gamemode gamemode = Gamemode.survival;

		Difficulty difficulty = Difficulty.normal;

		bool depleteHunger = true;
		
		bool doDaylightCycle = true;

		bool doEntityDrops = true;

		bool doFireTick = true;
		
		bool doScheduledTicks = true;
		
		bool doWeatherCycle = true;

		bool naturalRegeneration = true;
		
		bool pvp = true;
		
		uint randomTickSpeed = 3;

		uint viewDistance = 10;
		
		bool aboutCommand = true;

		bool helpCommand = true;

		bool permissionCommand = true;

		bool stopCommand = true;

		bool transferCommand = true;

		bool worldCommand = true;

		public this() {

			this.ip = getAddress("localhost")[0].toAddrString();

		}

	}

	/**
	 * Loads the configuration for the first time.
	 */
	public void load() {}

	/**
	 * Reloads the configuration.
	 */
	public void reload() {}

	/**
	 * Saves the configuration.
	 */
	public void save() {}

}

/**
 * File manager for assets and temp files.
 */
class Files {
	
	public immutable string assets;
	public immutable string temp;
	
	public this(string assets, string temp) {
		if(!assets.endsWith(dirSeparator)) assets ~= dirSeparator;
		this.assets = assets;
		if(!temp.endsWith(dirSeparator)) temp ~= dirSeparator;
		this.temp = temp;
	}
	
	/**
	 * Indicates whether an asset exists.
	 * Returns: true if the asset exists, false otherwise
	 */
	public inout bool hasAsset(string file) {
		return exists(this.assets ~ file) && isFile(this.assets ~ file);
	}
	
	/**
	 * Reads the content of an asset.
	 * Throws: FileException if the file cannot be found.
	 */
	public inout void[] readAsset(string file) {
		return read(this.assets ~ file);
	}

	public inout bool hasPluginAsset(Plugin plugin, string file) {
		return exists(plugin.path ~ "assets" ~ dirSeparator ~ file);
	}

	public inout void[] readPluginAsset(Plugin plugin, string file) {
		return read(plugin.path ~ "assets" ~ dirSeparator ~ file);
	}
	
	/**
	 * Indicates whether a temp file exists.
	 */
	public inout bool hasTemp(string file) {
		return exists(this.temp ~ temp) && isFile(this.temp ~ file);
	}
	
	/**
	 * Reads the content of a temp file.
	 */
	public inout void[] readTemp(string file) {
		return read(this.temp ~ file);
	}
	
	/**
	 * Writes buffer to a temp file.
	 */
	public inout void writeTemp(string file, const(void)[] buffer) {
		return write(this.temp ~ file, buffer);
	}
	
}

//TODO move to selery/lang.d
public string bestLanguage(string lang, string[] accepted) {
	if(accepted.canFind(lang)) return lang;
	string similar = lang[0..lang.indexOf("_")+1];
	foreach(al ; accepted) {
		if(al.startsWith(similar)) return al;
	}
	return accepted.canFind("en_GB") ? "en_GB" : accepted[0];
}
