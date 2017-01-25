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
module sel.event.world.entity;

import std.algorithm : max;
import std.conv : to;

import sel.player : Player;
import sel.entity.effect : Effects;
import sel.entity.entity : Entity;
import sel.entity.interfaces : Undead, Arthropods;
import sel.entity.human : Human;
import sel.entity.living : Living, Damage;
import sel.event.event : Cancellable;
import sel.event.world.damage : EntityDamageEvent;
import sel.event.world.world;
import sel.item.enchanting : Enchantments;
import sel.item.item : Item;
import sel.item.slot : Slot;
import sel.item.tool : Tool;
import sel.math.vector : EntityPosition;
import sel.world.world : World;

interface EntityEvent : WorldEvent {

	public pure nothrow @property @safe @nogc Entity entity();

	public static mixin template Implementation() {

		private Entity n_entity;

		public final override pure nothrow @property @safe @nogc Entity entity() {
			return this.n_entity;
		}

		// implements WorldEvent
		public final override pure nothrow @property @safe @nogc World world() {
			return this.entity.world;
		}

	}
	
}

final class EntityHealEvent : EntityEvent, Cancellable {

	mixin Cancellable.Implementation;

	mixin EntityEvent.Implementation;

	private ubyte n_cause;
	private uint n_amount;

	public @safe @nogc this(Living entity, ubyte cause, uint amount) {
		this.n_entity = entity;
		this.n_cause = cause;
		this.n_amount = amount;
	}

	public @property @safe @nogc ubyte cause() {
		return this.n_cause;
	}

	public @property @safe @nogc uint amount() {
		return this.n_amount;
	}

}

final class EntityDeathEvent : EntityEvent {

	mixin EntityEvent.Implementation;

	private EntityDamageEvent n_damage;

	private string m_message;
	private string[] m_args;

	public @safe this(Living entity, EntityDamageEvent damage) {
		this.n_entity = entity;
		this.n_damage = damage;
		if(cast(Player)entity) this.message = true;
	}

	public pure nothrow @property @safe @nogc EntityDamageEvent damageEvent() {
		return this.n_damage;
	}

	public pure nothrow @property @safe @nogc string message() {
		return this.m_message;
	}

	public pure nothrow @property @safe string message(string message) {
		return this.m_message = message is null ? "" : message;
	}

	public pure nothrow @property @safe string message(bool display) {
		if(display) {
			this.m_message = this.damageEvent.message;
			this.m_args = this.damageEvent.args;
		} else {
			this.m_message = "";
			this.m_args.length = 0;
		}
		return this.message;
	}

	public pure nothrow @property @safe @nogc string[] args() {
		return this.m_args;
	}

	public pure nothrow @property @safe string[] args(string[] args) {
		return this.m_args = args is null ? [] : args;
	}

}
