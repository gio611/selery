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
 * Source: $(HTTP github.com/sel-project/selery/source/selery/world/world.d, selery/world/world.d)
 */
module selery.world.world;

import core.atomic : atomicOp;
import core.thread : Thread;

import std.algorithm : sort, min, canFind;
static import std.concurrency;
import std.conv : to;
import std.datetime : dur;
import std.datetime.stopwatch : StopWatch;
import std.math : sin, cos, PI, pow;
import std.random : Random, unpredictableSeed, uniform, uniform01, dice;
import std.string : replace, toLower, toUpper, join;
import std.traits : Parameters;
import std.typecons : Tuple;
import std.typetuple : TypeTuple;

import sel.format : Format;

import selery.about;
import selery.block.block : Block, PlacedBlock, Update, Remove, blockInto;
import selery.block.blocks : BlockStorage, Blocks;
import selery.block.tile : Tile;
import selery.command.command : Command;
import selery.command.util : WorldCommandSender;
import selery.config : Config;
import selery.config : Gamemode, Difficulty, Dimension;
import selery.entity.entity : Entity;
import selery.entity.living : Living;
import selery.entity.noai : ItemEntity, Lightning;
import selery.event.event : Event, EventListener;
import selery.event.world.entity : EntityEvent;
import selery.event.world.player : PlayerEvent, PlayerSpawnEvent, PlayerAfterSpawnEvent, PlayerDespawnEvent, PlayerAfterDespawnEvent;
import selery.event.world.world : WorldEvent;
import selery.item.item : Item;
import selery.item.items : ItemStorage, Items;
import selery.item.slot : Slot;
import selery.lang : Translation;
import selery.log : Message;
import selery.math.vector;
import selery.node.server : NodeServer;
import selery.player.bedrock : BedrockPlayerImpl;
import selery.player.java : JavaPlayerImpl;
import selery.player.player : PlayerInfo, Player, isPlayer;
import selery.plugin : Plugin, loadPluginAttributes, Description;
import selery.util.color : Color;
import selery.util.util : call;
import selery.world.chunk;
import selery.world.generator;
import selery.world.group;
import selery.world.map : Map;
import selery.world.task : TaskManager;

static import sul.blocks;

private shared uint _id;

final class WorldInfo {

	public immutable uint id;

	public shared GroupInfo group;

	public size_t entities;

	public size_t players;

	public size_t chunks;

	public shared this() {
		this.id = atomicOp!"+="(_id, 1);
	}

}

/**
 * Basic world.
 */
class World : EventListener!(WorldEvent, EntityEvent, "entity", PlayerEvent, "player") {

	public shared WorldInfo info;

	private bool _started = false;
	private bool _stopped = false;

	protected Dimension n_dimension = Dimension.overworld;
	protected uint n_seed;
	protected string n_type;

	private int _state = -1;
	public void delegate(int, uint) _update_state;

	private WorldGroup group;
	
	protected BlockStorage n_blocks;
	protected ItemStorage n_items;
	
	private Random _random;
	
	private tick_t n_ticks = 0;

	protected Generator generator;
	
	public BlockPosition spawnPoint;
	
	private Chunk[int][int] n_chunks;
	public ChunkPosition[] defaultChunks;

	private Map[int][int][ubyte] maps;
	private Map[ushort] id_maps;

	public bool updateBlocks = false;

	//TODO move in chunks

	private PlacedBlock[] updated_blocks;
	private Tile[size_t] updated_tiles;
	
	private Entity[size_t] w_entities;
	private Player[size_t] w_players;

	private ScheduledUpdate[] scheduled_updates;

	private TaskManager tasks;

	private Command[string] commands;
	
	public this(Generator generator=null, uint seed=unpredictableSeed) {
		this.info = new shared WorldInfo();
		this.n_seed = seed;
		if(this.n_blocks is null) this.n_blocks = new BlockStorage();
		if(this.n_items is null) this.n_items = new ItemStorage();
		this._random = Random(this.seed);
		this.generator = generator is null ? new Flat(this) : generator;
		this.generator.seed = seed;
		this.n_type = this.generator.type;
		this.spawnPoint = this.generator.spawn;
		this.tasks = new TaskManager();
	}
	
	public this(uint seed) {
		this(null, seed);
	}

	public final pure nothrow @property @safe @nogc uint id() {
		return this.info.id;
	}

	/*
	 * Function called when the the world is created.
	 * Calls init and orders the default chunks.
	 */
	public void start(WorldGroup group) {
		this.group = group;
		this.initChunks();
		this.updated_blocks.length = 0;
		sort!"a.x.abs + a.z.abs < b.x.abs + b.z.abs"(this.defaultChunks);
		this.updateBlocks = true;
	}

	/*
	 * Initialise chunks.
	 */
	protected void initChunks() {
		
		immutable int radius = 5;
		//load some chunks as a flat world
		foreach(int x ; -radius..radius) {
			foreach(int z ; -radius..radius) {
				if(!(x == -radius && z == -radius) && !(x == radius-1 && z == radius-1) && !(x == -radius && z == radius-1) && !(x == radius-1 && z == -radius)) {
					this.generate(x, z);
					this.defaultChunks ~= ChunkPosition(x, z);
				}
			}
		}

	}

	/*
	 * Function called when the world is closed.
	 * Saves the resources if they need to be saved and unloads the chunks
	 * freeing the memory allocated.
	 */
	public void stop() {
		foreach(ref chunks ; this.n_chunks) {
			foreach(ref chunk ; chunks) {
				chunk.unload();
			}
		}
	}

	public final pure nothrow @property @safe @nogc shared(NodeServer) server() {
		return this.group.server;
	}

	/**
	 * Gets the world's seed used for terrain and randomness
	 * generation.
	 */
	public final pure nothrow @property @safe @nogc const(uint) seed() {
		return this.n_seed;
	}

	/**
	 * Gets the world's type as a string.
	 * Valid types are "flat" and "default" for both Minecraft and
	 * Minecraft: Pocket Edition plus "largeBiomes", "amplified" and
	 * "customized" for Minecraft only.
	 */
	public final pure nothrow @property @safe @nogc const(string) type() {
		return this.n_type;
	}
	
	/**
	 * Gets the world's dimension as a group of bytes.
	 * Example:
	 * ---
	 * if(world.dimension == Dimension.nether) {
	 *    log("world is nether!");
	 * }
	 * ---
	 */
	public final pure nothrow @property @safe @nogc Dimension dimension() {
		return this.n_dimension;
	}

	/**
	 * Gets/sets the world's gamemode.
	 */
	public final pure nothrow @property @safe @nogc Gamemode gamemode() {
		return this.group.gamemode;
	}

	/// ditto
	public final @property Gamemode gamemode(Gamemode gamemode) {
		this.group.updateGamemode(gamemode);
		return gamemode;
	}

	/**
	 * Gets/sets the world's difficulty.
	 */
	public final pure nothrow @property @safe @nogc Difficulty difficulty() {
		return this.group.difficulty;
	}

	/// ditto
	public final @property Difficulty difficulty(Difficulty difficulty) {
		this.group.updateDifficulty(difficulty);
		return difficulty;
	}

	/**
	 * Gets/sets whether the pvp (player vs player) is active in the
	 * current group of worlds.
	 */
	public final pure nothrow @property @safe @nogc bool pvp() {
		return this.group.pvp;
	}

	/// ditto
	public final pure nothrow @property @safe @nogc bool pvp(bool pvp) {
		return this.group.pvp = pvp;
	}

	/**
	 * Gets/sets whether player's health regenerates naturally or not.
	 */
	public final pure nothrow @property @safe @nogc bool naturalRegeneration() {
		return this.group.naturalRegeneration;
	}

	/// ditto
	public final pure nothrow @property @safe @nogc bool naturalRegeneration(bool naturalRegeneration) {
		return this.group.naturalRegeneration = naturalRegeneration;
	}

	/**
	 * Gets/sets whether players' hunger is depleted when the world's difficulty
	 * is not set to peaceful.
	 */
	public final pure nothrow @property @safe @nogc bool depleteHunger() {
		return this.group.depleteHunger;
	}

	/// ditto
	public final pure nothrow @property @safe @nogc bool depleteHunger(bool depleteHunger) {
		return this.group.depleteHunger = depleteHunger;
	}

	/**
	 * Gets the world's time manager.
	 * Example:
	 * ---
	 * log("Time of the day is ", world.time.time);
	 * log("Day is ", world.time.day);
	 * log("Do daylight cycle? ", world.time.cycle);
	 * world.time = 25000;
	 * assert(world.time == 1000);
	 * world.time = Time.noon;
	 * ---
	 */
	public final pure nothrow @property @safe @nogc auto time() {
		return this.group.time;
	}

	/**
	 * Gets the world's weather manager.
	 * Example:
	 * ---
	 * log("is it raining? ", world.weather.raining);
	 * log("do weather cycle? ", world.weather.cycle);
	 * world.weather.start();
	 * world.weather.clear();
	 * world.weather.start(24000);
	 * assert(world.weather.raining);
	 * ---
	 */
	public final pure nothrow @property @safe @nogc auto weather() {
		return this.group.weather;
	}

	/**
	 * Gets/sets the worlds group's default highest view distance for players.
	 */
	public final pure nothrow @property @safe @nogc uint viewDistance() {
		return this.group.viewDistance;
	}

	/// ditto
	public final pure nothrow @property @safe @nogc uint viewDistance(uint viewDistance) {
		return this.group.viewDistance = viewDistance;
	}

	/**
	 * Gets/sets the world's random tick speed.
	 */
	public final pure nothrow @property @safe @nogc uint randomTickSpeed() {
		return this.group.randomTickSpeed;
	}

	/// ditto
	public final pure nothrow @property @safe @nogc uint randomTickSpeed(uint randomTickSpeed) {
		return this.group.randomTickSpeed = randomTickSpeed;
	}
	
	/*
	 * Gets the world's blocks.
	 */
	public final pure nothrow @property @safe @nogc ref BlockStorage blocks() {
		return this.n_blocks;
	}
	
	/*
	 * Gets the world's items.
	 */
	public final pure nothrow @property @safe @nogc ref ItemStorage items() {
		return this.n_items;
	}
	
	/**
	 * Gets the world's random generator initialised with the
	 * world's seed.
	 */
	public final pure nothrow @property @safe @nogc ref Random random() {
		return this._random;
	}

	/**
	 * Gets the current world's state.
	 */
	public final pure nothrow @property @safe @nogc uint currentState() {
		return this._state;
	}

	/*
	 * Updates the world's state.
	 */
	public final void updateState(uint state) {
		if(this._state != state) {
			this._update_state(this._state, state);
			this._state = state;
		}
	}
	
	/*
	 * Ticks the world and its children.
	 * This function should be called by the startMainWorldLoop function
	 * (if parent world is null) or by the parent world (if it is not null).
	 */
	public void tick() {

		this.n_ticks++;

		// tasks
		if(this.tasks.length) this.tasks.tick(this.ticks);

		// random chunk ticks
		//if(this.rules.chunkTick) {
			foreach(ref c ; this.n_chunks) {
				foreach(ref chunk ; c) {
					int cx = chunk.x << 4;
					int cz = chunk.z << 4;
					if(this.weather.thunderous && uniform01!float(this.random) < 1f/100_000) {
						ubyte random = uniform!ubyte(this.random);
						ubyte x = (random >> 4) & 0xF;
						ubyte z = random & 0xF;
						auto y = chunk.firstBlock(x, z);
						if(y >= 0) this.strike(EntityPosition(chunk.x << 4 | x, y, chunk.z << 4 | z));
					}
					if(this.weather.raining && uniform01!float(this.random) < .03125f * this.weather.intensity) {
						auto xz = chunk.nextSnow;
						auto y = chunk.firstBlock(xz.x, xz.z);
						if(y > 0) {
							immutable temperature = chunk.biomes[xz.z << 4 | xz.x].temperature - (.05f / 30) * min(0, y - 64);
							if(temperature <= .95) {
								BlockPosition position = BlockPosition(cx | xz.x, y, cz | xz.z);
								Block dest = this[position];
								if(temperature > .15) {
									if(dest == Blocks.cauldron[0..$-1]) {
										//TODO add 1 water level to cauldron
									}
								} else {
									if(dest == Blocks.flowingWater0 || dest == Blocks.stillWater0) {
										//TODO check block's light level (less than 13)
										// change water into ice
										this[position] = Blocks.ice;
									} else if(dest.fullUpperShape && dest.opacity == 15) {
										//TODO check block's light level
										// add a snow layer
										this[position + [0, 1, 0]] = Blocks.snowLayer0;
									}
								}
							}
						}
					}
					foreach(i, section; chunk.sections) {
						if(section.tick) {
							immutable y = i << 4;
							foreach(j ; 0..this.randomTickSpeed) {
								auto random = uniform(0, 4096, this.random);
								auto block = section.blocks[random];
								if(block && (*block).doRandomTick) {
									(*block).onRandomTick(this, BlockPosition(cx | ((random >> 4) & 15), y | ((random >> 8) & 15), cz | (random & 15)));
								}
							}
						}
					}
				}
			}
		//}

		// scheduled updates
		/*if(this.scheduled_updates.length > 0) {
			for(uint i=0; i<this.scheduled_updates.length; i++) {
				if(this.scheduled_updates[i].time-- == 0) {
					this.scheduled_updates[i].block.onScheduledUpdate();
					this.scheduled_updates = this.scheduled_updates[0..i] ~ this.scheduled_updates[i+1..$];
				}
			}
		}*/
		
		// tick the entities
		foreach(ref Entity entity ; this.w_entities) {
			if(entity.ticking) entity.tick();
		}
		// and the players
		foreach(ref Player player ; this.w_players) {
			if(player.ticking) player.tick();
		}

		// send the updated movements
		foreach(ref Player player ; this.w_players) {
			player.sendMovements();
		}

		// set the entities as non-moved
		foreach(ref Entity entity ; this.w_entities) {
			if(entity.moved) {
				entity.moved = false;
				entity.oldposition = entity.position;
			}
			if(entity.motionmoved) entity.motionmoved = false;
		}
		foreach(ref Player player ; this.w_players) {
			if(player.moved) {
				player.moved = false;
				player.oldposition = player.position;
			}
			if(player.motionmoved) player.motionmoved = false;
		}

		// send the updated blocks
		if(this.updated_blocks.length > 0) {
			this.w_players.call!"sendBlocks"(this.updated_blocks);
			this.updated_blocks.length = 0;
		}

		// send the updated tiles
		if(this.updated_tiles.length > 0) {
			foreach(Tile tile ; this.updated_tiles) {
				this.w_players.call!"sendTile"(tile, false);
			}
			//reset
			this.updated_tiles.clear();
		}

	}
	
	/**
	 * Gets the number of this ticks occurred since the
	 * creation of the world.
	 */
	public final pure nothrow @property @safe @nogc tick_t ticks() {
		return this.n_ticks;
	}
	
	/**
	 * Logs a message into the server's console as this world but without
	 * sending it to the players.
	 */
	public void log(E...)(E args) {
		this.logImpl(Message.convert(args));
	}
	
	protected void logImpl(Message[] messages) {
		this.server.logWorld(messages, this.id); //TODO that doesn't print the world's name in standalone nodes
	}

	/**
	 * Broadcasts a message (raw or translatable) to every player in the world.
	 * To broadcast a message to every player in the group, use `group.broadcast`.
	 */
	public void broadcast(E...)(E args) {
		static if(E.length == 1 && is(E[0] == Message[])) this.broadcastImpl(args[0]);
		else this.broadcastImpl(Message.convert(args));
	}

	protected void broadcastImpl(Message[] message) {
		foreach(player ; this.players) player.sendMessage(message);
		this.logImpl(message);
	}

	/**
	 * Broadcasts a tip to the players in the world.
	 */
	public final void broadcastTip(E...)(E args) {
		this.broadcastTipImpl(Message.convert(args));
	}

	protected void broadcastTipImpl(Message[] message) {
		foreach(player ; this.players) player.sendTip(message);
	}

	/**
	 * Gets the entities spawned in the world.
	 */
	public @property T[] entities(T=Entity, string condition="")() {
		import std.algorithm : filter;
		T[] ret;
		void add(E)(E entity) {
			T a = cast(T)entity;
			if(a) {
				static if(condition.length) {
					mixin("if(" ~ condition ~ ") ret ~= a;");
				} else {
					ret ~= a;
				}
			}
		}
		//TODO improve performances for Player and Entity
		foreach(entity ; this.w_entities) add(entity);
		foreach(player ; this.w_players) add(player);
		return ret;
	}

	/// ditto
	public @property Entity[] entities(string condition)() {
		return this.entities!(Entity, condition);
	}

	/**
	 * Gets a list of the players spawned in the world.
	 */
	public @property T[] players(T=Player, string condition="")() if(isPlayer!T) {
		return this.entities!(T, condition);
	}

	/// ditto
	public @property Player[] players(string condition)() {
		return this.players!(Player, condition);
	}

	/*
	 * Prepares a player for spawning.
	 */
	public void preSpawnPlayer(Player player) {

		player.spawn = this.spawnPoint; // send spawn position
		player.move(this.spawnPoint.entityPosition); // send position

		player.sendResourcePack(); //TODO world's resource pack
		
		//send chunks
		foreach(ChunkPosition pos ; this.defaultChunks) {
			auto chunk = pos in this;
			if(chunk) {
				player.sendChunk(*chunk);
			} else {
				player.sendChunk(this.generate(pos));
			}
			player.loaded_chunks ~= pos;
		}

		// add world's commands
		foreach(command ; this.commands) {
			player.registerCommand(command);
		}

		player.sendSettingsPacket();
		player.sendRespawnPacket();
		player.sendInventory();
		player.sendMetadata(player);

		player.setAsReadyToSpawn();
		player.firstspawn();

		this.w_players[player.id] = player;
		
		// player may have been teleported during the event, also fixes #8
		player.oldposition = this.spawnPoint.entityPosition;

	}

	/*
	 * Spawns and optionally announce a player.
	 */
	public void afterSpawnPlayer(Player player, bool announce) {

		// call the spawn event and broadcast message
		auto event = new PlayerSpawnEvent(player, announce);
		this.callEvent(event);
		if(event.announce) this.group.broadcast(event.message);

		//TODO let the event choose if spawn or not
		foreach(splayer ; this.w_players) {
			splayer.show(player);
			player.show(splayer);
		}

		foreach(entity ; this.w_entities) {
			if(entity.shouldSee(player)) entity.show(player);
			/*if(player.shouldSee(entity))*/ player.show(entity); // the player sees  E V E R Y T H I N G
		}

		atomicOp!"+="(this.info.entities, 1);
		atomicOp!"+="(this.info.players, 1);

	}
	
	/*
	 * Despawns a player (i.e. on disconnection, on world change, ...).
	 */
	public void despawnPlayer(Player player) {

		//TODO some packet shouldn't be sent when the player is disconnecting or changing dimension
		if(this.w_players.remove(player.id)) {

			auto event = new PlayerDespawnEvent(player, true); //TODO do not announce when moved to another world in the same group
			this.callEvent(event);
			if(event.announce) this.group.broadcast(event.message);

			foreach(viewer ; player.viewers) {
				viewer.hide(player);
			}
			foreach(watch ; player.watchlist) {
				player.hide(watch/*, false*/); // updating the viewer's watchlist
			}

			atomicOp!"-="(this.info.entities, 1);
			atomicOp!"-="(this.info.players, 1);

			this.callEventIfExists!PlayerAfterDespawnEvent(player);

			// remove world's commands
			foreach(command ; this.commands) {
				player.unregisterCommand(command);
			}

		}

	}

	/**
     * Spawns an entity.
	 */
	public final T spawn(T:Entity, E...)(E args) if(!isPlayer!T) {
		T spawned = new T(this, args);
		this.w_entities[spawned.id] = spawned;
		//TODO call the event
		foreach(ref Entity entity ; this.w_entities) {
			if(entity.shouldSee(spawned)) entity.show(spawned);
			if(spawned.shouldSee(entity)) spawned.show(entity);
		}
		foreach(ref Player player ; this.w_players) {
			player.show(spawned); // player sees everything!
			if(spawned.shouldSee(player)) spawned.show(player);
		}
		atomicOp!"+="(this.info.entities, 1);
		return spawned;
	}

	/+public final void spawn(Entity entity) {
		assert(entity.world == this);
	}+/

	/**
	 * Despawns an entity.
	 */
	public final void despawn(T:Entity)(T entity) if(!isPlayer!T) {
		if(entity.id in this.w_entities) {
			entity.setAsDespawned();
			this.w_entities.remove(entity.id);
			//TODO call the event
			foreach(ref Entity e ; entity.viewers) {
				e.hide(entity);
			}
			foreach(ref Entity e ; entity.watchlist) {
				entity.hide(e);
			}
			atomicOp!"-="(this.info.entities, 1);
		}
	}

	/**
	 * Drops an item.
	 */
	public final ItemEntity drop(Slot slot, EntityPosition position, EntityPosition motion) {
		if(!slot.empty) {
			return this.spawn!ItemEntity(position, motion, slot);
		} else {
			return null;
		}
	}

	/// ditto
	public final ItemEntity drop(Slot slot, EntityPosition position) {
		float f0 = uniform01!float(this.random) * .1f;
		float f1 = uniform01!float(this.random) * PI * 2f;
		return this.drop(slot, position, EntityPosition(-sin(f1) * f0, .2f, cos(f1) * f0));
	}

	/// ditto
	public final void drop(Block from, BlockPosition position) {
		foreach(slot ; from.drops(this, null, null)) {
			this.drop(slot, position.entityPosition + .5);
		}
	}

	/**
	 * Stikes a lightning.
	 */
	public final void strike(bool visual=false)(EntityPosition position) {
		this.w_players.call!"sendLightning"(new Lightning(this, position));
		static if(!visual) {
			//TODO do the damages
			//TODO create the fire
		}
	}

	/// ditto
	public final void strike(Entity entity) {
		this.strike(entity.position);
	}

	public void explode(bool breakBlocks=true)(EntityPosition position, float power, Living damager=null) {

		enum float rays = 16;
		enum float half_rays = (rays - 1) / 2;

		enum float length = .3;
		enum float attenuation = length * .75;
		
		Tuple!(BlockPosition, Block*)[] explodedBlocks;

		void explodeImpl(EntityPosition ray) {

			auto pointer = position.dup;
		
			for(double blastForce=uniform!"[]"(.4f, 1.3f, this.random)*power; blastForce>0; blastForce-=attenuation) {
				auto pos = cast(BlockPosition)pointer + [pointer.x < 0 ? 0 : 1, pointer.y < 0 ? 0 : 1, pointer.z < 0 ? 0 : 1];
				//if(pos.y < 0 || pos.y >= 256) break; //TODO use a constant
				auto block = pos in this;
				if(block) {
					blastForce -= ((*block).blastResistance / 5 + length) * length;
					if(blastForce <= 0) break;
					static if(breakBlocks) {
						import std.typecons : tuple;
						explodedBlocks ~= tuple(pos, block);
					}
				}
				pointer += ray;
			}

		}

		template Range(float max, E...) {
			static if(E.length >= max) {
				alias Range = E;
			} else {
				alias Range = Range!(max, E, E[$-1] + 1);
			}
		}

		foreach(x ; Range!(rays, 0)) {
			foreach(y ; Range!(rays, 0)) {
				foreach(z ; Range!(rays, 0)) {
					static if(x == 0 || x == rays - 1 || y == 0 || y == rays - 1 || z == 0 || z == rays - 1) {

						enum ray = (){
							auto ret = EntityPosition(x, y, z) / half_rays - 1;
							ret.length = length;
							return ret;
						}();
						explodeImpl(ray);

					}
				}
			}
		}

		// send packets
		this.players.call!"sendExplosion"(position, power, new Vector3!byte[0]);

		foreach(exploded ; explodedBlocks) {
			auto block = this[exploded[0]];
			if(block != Blocks.air) {
				this.opIndexAssign!true(Blocks.air, exploded[0]); //TODO use packet's fields
				if(this.random.range(0f, power) <= 1) {
					this.drop(block, exploded[0]);
					//TODO drop experience
				}
			}
		}

	}

	public void explode(bool breakBlocks=true)(BlockPosition position, float power, Living damager=null) {
		return this.explode!(breakBlocks)(position.entityPosition, power, damager);
	}

	/**
	 * Gets an entity from an id.
	 */
	public final @safe Entity entity(uint eid) {
		auto ret = eid in this.w_entities;
		return ret ? *ret : this.player(eid);
	}

	/**
	 * Gets a player from an id.
	 */
	public final @safe Player player(uint eid) {
		auto ret = eid in this.w_players;
		return ret ? *ret : null;
	}

	// CHUNKS

	/**
	 * Gets an associative array with every chunk loaded in
	 * the world.
	 */
	public final pure nothrow @property @safe @nogc Chunk[int][int] chunks() {
		return this.n_chunks;
	}

	/**
	 * Gets the number of loaded chunks in the world and
	 * its children.
	 */
	public final pure @property @safe @nogc size_t loadedChunks(bool children=false)() {
		size_t ret = 0;
		foreach(chunks ; this.n_chunks) {
			ret += chunks.length;
		}
		static if(children) {
			foreach(child ; this.n_children) {
				ret += child.loadedChunks!true;
			}
		}
		return ret;
	}

	/**
	 * Gets a chunk.
	 * Returns: the chunk at given position or null if the chunk doesn't exist
	 */
	public final @safe Chunk opIndex(int x, int z) {
		return this.opIndex(ChunkPosition(x, z));
	}

	/// ditto
	public final @safe Chunk opIndex(ChunkPosition position) {
		auto ret = position in this;
		return ret ? *ret : null;
	}

	/**
	 * Gets a pointer to the chunk at the given position.
	 * Example:
	 * ---
	 * if(ChunkPosition(100, 100) in world) {
	 *    log("world doesn't have the chunk at 100, 100");
	 * }
	 * ---
	 */
	public final @safe Chunk* opBinaryRight(string op : "in")(ChunkPosition position) {
		auto a = position.x in this.n_chunks;
		return a ? position.z in *a : null;
	}
	
	/**
	 * Sets a chunk.
	 * Example:
	 * ---
	 * auto chunk = new Chunk(world, ChunkPosition(1, 2));
	 * world[] = chunk;
	 * assert(world[1, 2] == chunk);
	 * ---
	 */
	public final Chunk opIndexAssign(Chunk chunk) {
		atomicOp!"+="(this.info.chunks, 1);
		chunk.saveChangedBlocks = true;
		return this.n_chunks[chunk.x][chunk.z] = chunk;
	}

	/**
	 * Generates and sets a chunk.
	 * Returns: the generated chunk
	 */
	public Chunk generate(ChunkPosition position) {
		return this[] = this.generator.generate(position);
	}

	/// ditto
	public Chunk generate(int x, int z) {
		return this.generate(ChunkPosition(x, z));
	}

	/**
	 * Unloads and removes a chunk.
	 * Returns: true if the chunk was removed, false otherwise
	 */
	public bool unload(ChunkPosition position) {
		if(this.defaultChunks.canFind(position)) return false;
		auto chunk = position in this;
		if(chunk) {
			this.n_chunks[position.x].remove(position.z);
			if(this.n_chunks[position.x].length == 0) this.n_chunks.remove(position.x);
			(*chunk).unload();
			return true;
		}
		return false;
	}

	// Handles the player's chunk request
	public final void playerUpdateRadius(Player player) {
		if(player.viewDistance > this.viewDistance) player.viewDistance = this.viewDistance;
		//TODO allow disallowing auto-sending
		//if(this.rules.chunksAutosending) {
			ChunkPosition pos = player.chunk;
			if(player.last_chunk_position != pos) {
				player.last_chunk_position = pos;

				ChunkPosition[] new_chunks;
				foreach(int x ; pos.x-player.viewDistance.to!int..pos.x+player.viewDistance.to!int) {
					foreach(int z ; pos.z-player.viewDistance.to!int..pos.z+player.viewDistance.to!int) {
						ChunkPosition c = ChunkPosition(x, z);
						if(distance(c, pos) <= player.viewDistance) {
							new_chunks ~= c;
						}
					}
				}

				// sort 'em
				sort!"a.x + a.z < b.x + b.z"(new_chunks);

				// send chunks
				foreach(ChunkPosition cp ; new_chunks) {
					if(!player.loaded_chunks.canFind(cp)) {
						auto chunk = cp in this;
						if(chunk) {
							player.sendChunk(*chunk);
						} else {
							player.sendChunk(this.generate(cp));
						}
					}
				}

				// unload chunks
				foreach(ref ChunkPosition c ; player.loaded_chunks) {
					if(!new_chunks.canFind(c)) {
						//TODO check if it should be deleted from the world's memory
						//this.unload(this[c]);
						player.unloadChunk(c);
					}
				}

				// set the new chunks
				player.loaded_chunks = new_chunks;

			}
		//}

	}

	// BLOCKS

	/**
	 * Gets a block.
	 * Returns: an instance of block, which is never null
	 * Example:
	 * ---
	 * if(world[0, 0, 0] != Blocks.BEDROCK) {
	 *    log("0,0,0 is not bedrock!");
	 * }
	 * ---
	 */
	public Block opIndex(BlockPosition position) {
		auto block = position in this;
		return block ? *block : *this.blocks[0]; // default block (air)
	}

	/// ditto
	public Block opIndex(int x, uint y, int z) {
		return this.opIndex(BlockPosition(x, y, z));
	}

	//TODO documentation
	public Block* opBinaryRight(string op : "in")(BlockPosition position) {
		auto chunk = ChunkPosition(position.x >> 4, position.z >> 4) in this;
		return chunk ? (*chunk)[position.x & 15, position.y, position.z & 15] : null;
	}

	/**
	 * Gets a tile.
	 */
	public @safe T tileAt(T=Tile)(int x, uint y, int z) if(is(T == class) || is(T == interface)) {
		auto chunk = ChunkPosition(x >> 4, z >> 4) in this;
		return chunk ? (*chunk).tileAt!T(BlockPosition(x & 15, y, z & 15)) : null;
	}

	/// ditto
	public @safe T tileAt(T=Tile)(BlockPosition position) {
		return this.tileAt!T(position.x, position.y, position.z);
	}

	/**
	 * Sets a block.
	 * Example:
	 * ---
	 * world[0, 55, 12] = Blocks.grass;
	 * world[12, 55, 789] = Blocks.chest; // not a tile!
	 * ---
	 */
	public Block* opIndexAssign(bool sendUpdates=true, T)(T block, BlockPosition position) if(is(T == block_t) || is(T == block_t[]) || is(T == Block*)) {
		auto chunk = ChunkPosition(position.x >> 4, position.z >> 4) in this;
		if(chunk) {

			Block* ptr = (*chunk)[position.x & 15, position.y, position.z & 15];
			if(ptr) {
				(*ptr).onRemoved(this, position, Remove.unset);
			}

			static if(is(T == block_t[])) {
				block_t b = block[0];
			} else {
				alias b = block;
			}

			Block* nb = ((*chunk)[position.x & 15, position.y, position.z & 15] = b);

			// set as to update
			//TODO move this in the chunk
			static if(sendUpdates) this.updated_blocks ~= PlacedBlock(position, nb ? (*nb).data : sul.blocks.Blocks.air);

			// call the update function
			if(this.updateBlocks) {
				if(nb) (*nb).onUpdated(this, position, Update.placed);
				this.updateBlock(position + [0, 1, 0]);
				this.updateBlock(position + [1, 0, 0]);
				this.updateBlock(position + [0, 0, 1]);
				this.updateBlock(position - [0, 1, 0]);
				this.updateBlock(position - [1, 0, 0]);
				this.updateBlock(position - [0, 0, 1]);
			}

			return nb;

		}
		return null;
	}

	/// ditto
	public Block* opIndexAssign(T)(T block, int x, uint y, int z) if(is(T == block_t) || is(T == block_t[]) || is(T == Block*)) {
		return this.opIndexAssign(block, BlockPosition(x, y, z));
	}

	/**
	 * Sets a tile.
	 */
	public void opIndexAssign(T)(T tile, BlockPosition position) if(is(T : Tile) && is(T : Block)) {
		assert(!tile.placed, "This tile has already been placed: " ~ to!string(tile) ~ " at " ~ to!string(position));
		// place the block
		this[position] = tile.id;
		auto chunk = ChunkPosition(position.x >> 4, position.z >> 4) in this;
		if(chunk) {
			// then set it as placed here
			tile.place(this, position);
			// and register the tile in the chunk
			(*chunk).registerTile(tile);
		}
	}

	/// ditto
	public void opIndexAssign(T)(T tile, int x, uint y, int z) if(is(T : Tile) && is(T : Block)) {
		this.opIndexAssign(tile, BlockPosition(x, y, z));
	}

	/**
	 * Sets the same block in a rectangualar area.
	 * This method is optimised for building as it uses a cached pointer
	 * instead of getting it every time and it doesn't call any block
	 * update.
	 * Example:
	 * ---
	 * // sets a chunk to stone
	 * world[0..16, 0..$, 0..16] = Blocks.stone;
	 * 
	 * // sets an area to air
	 * world[0..16, 64..128, 0..16] = Blocks.air;
	 * 
	 * // sets a 1-block-high layer only
	 * world[0..16, 64, 0..16] = Blocks.beetroot0;
	 * ---
	 */
	public final void opIndexAssign(block_t b, Slice x, Slice y, Slice z) {
		auto block = b in this.blocks;
		this.updateBlocks = false;
		foreach(px ; x.min..x.max) {
			foreach(py ; y.min..y.max) {
				foreach(pz ; z.min..z.max) {
					this[px, py, pz] = block;
				}
			}
		}
		this.updateBlocks = true;
	}

	/// ditto
	public final void opIndexAssign(block_t b, int x, Slice y, Slice z) {
		this[x..x+1, y, z] = b;
	}

	/// ditto
	public final void opIndexAssign(block_t b, Slice x, uint y, Slice z) {
		this[x, y..y+1, z] = b;
	}

	/// ditto
	public final void opIndexAssign(block_t b, Slice x, Slice y, int z) {
		this[x, y, z..z+1] = b;
	}

	/// ditto
	public final void opIndexAssign(block_t b, int x, uint y, Slice z) {
		this[x..x+1, y..y+1, z] = b;
	}

	/// ditto
	public final void opIndexAssign(block_t b, int x, Slice y, int z) {
		this[x..x+1, y, z..z+1] = b;
	}

	/// ditto
	public final void opIndexAssign(block_t b, Slice x, uint y, int z) {
		this[x, y..y+1, z..z+1] = b;
	}

	public size_t replace(block_t from, block_t to) {
		return this.replace(from in this.blocks, to in this.blocks);
	}

	public size_t replace(Block* from, Block* to) {
		size_t ret = 0;
		foreach(cc ; this.n_chunks) {
			foreach(c ; cc) {
				ret += this.replaceImpl(c, from, to);
			}
		}
		return ret;
	}

	public size_t replace(block_t from, block_t to, BlockPosition fromp, BlockPosition top) {
		if(fromp.x < top.x && fromp.y < top.y && fromp.z < top.z) {
			//TODO
			return 0;
		} else {
			return 0;
		}
	}

	protected size_t replaceImpl(ref Chunk chunk, Block* from, Block* to) {
		//TODO
		return 0;
	}

	/// function called by a tile when its data is updated
	public final void updateTile(Tile tile, BlockPosition position) {
		this.updated_tiles[tile.tid] = tile;
	}

	protected final void updateBlock(BlockPosition position) {
		auto block = position in this;
		if(block) (*block).onUpdated(this, position, Update.nearestChanged);
	}

	public @safe Slice opSlice(size_t pos)(int min, int max) {
		return Slice(min, max);
	}

	/// schedules a block update
	public @safe void scheduleBlockUpdate(Block block, uint time) {
		/*if(this.rules.scheduledTicks) {
			this.scheduled_updates ~= ScheduledUpdate(block, time);
		}*/
	}

	/**
	 * Registers a command.
	 */
	public void registerCommand(alias func)(void delegate(Parameters!func) del, string command, Description description, string[] aliases, ubyte permissionLevel, string[] permissions, bool hidden, bool implemented=true) {
		command = command.toLower;
		if(command !in this.commands) this.commands[command] = new Command(command, description, aliases, permissionLevel, permissions, hidden);
		auto ptr = command in this.commands;
		(*ptr).add!func(del, implemented);
	}

	/**
	 * Unregisters a command.
	 */
	public void unregisterCommand(string command) {
		this.commands.remove(command);
	}

	/**
	 * Registers a task.
	 * Params:
	 *		task = a delegate of a function that will be called every interval
	 *		interval = number of ticks indicating between the calls
	 *		repeat = number of times to repeat the task
	 * Returns:
	 * 		the new task id that can be used to remove the task
	 */
	public @safe size_t addTask(void delegate() task, size_t interval, size_t repeat=size_t.max) {
		return this.tasks.add(task, interval, repeat, this.ticks);
	}
	
	/// ditto
	alias addTask schedule;
	
	/**
	 * Executes a task one time after the given ticks.
	 */
	public @safe size_t delay(void delegate() task, size_t timeout) {
		return this.addTask(task, timeout, 1);
	}
	
	/**
	 * Removes a task using the task's delegate or the id returned
	 * by the addTask function.
	 */
	public @safe void removeTask(void delegate() task) {
		this.tasks.remove(task);
	}
	
	/// ditto
	public @safe void removeTask(size_t tid) {
		this.tasks.remove(tid);
	}

	public override @safe bool opEquals(Object o) {
		if(cast(World)o) return this.id == (cast(World)o).id;
		else return false;
	}

	/** Grows a tree in the given world. */
	public static void growTree(World world, BlockPosition position, ushort[] trunk=Blocks.oakWood, ushort leaves=Blocks.oakLeavesDecay) {
		uint height = uniform(3u, 6u, world.random);
		foreach(uint i ; 0..height) {
			world[position + [0, i, 0]] = trunk[0];
		}

		foreach(uint i ; 0..2) {
			foreach(int x ; -2..3) {
				foreach(int z ; -2..3) {
					world[position + [x, height + i, z]] = leaves;
				}
			}
		}
		foreach(int x ; -1..2) {
			foreach(int z ; -1..2) {
				world[position + [x, height + 2, z]] = leaves;
			}
		}
		world[position + [0, height + 3, 0]] = leaves;
		world[position + [-1, height + 3, 0]] = leaves;
		world[position + [1, height + 3, 0]] = leaves;
		world[position + [0, height + 3, -1]] = leaves;
		world[position + [0, height + 3, 1]] = leaves;
	}

}

private alias Slice = Tuple!(int, "min", int, "max");

private struct ScheduledUpdate {

	public Block block;
	public uint time;

	public @safe @nogc this(ref Block block, uint time) {
		this.block = block;
		this.time = time;
	}

}

enum Time : uint {

	day = 1000,
	night = 13000,
	midnight = 18000,
	noon = 6000,
	sunrise = 23000,
	sunset = 12000,

}
