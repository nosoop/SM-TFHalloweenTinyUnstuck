/**
 * [TF2] Halloween Tiny Unstuck
 */
#pragma semicolon 1
#include <sourcemod>

#include <dhooks>
#include <sdktools>

#pragma newdecls required

#define PLUGIN_VERSION "1.2.0"
public Plugin myinfo = {
	name = "[TF2] Halloween Tiny Unstuck",
	author = "nosoop",
	description = "Prevents players from dying when getting out of being tiny.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFHalloweenTinyUnstuck"
}

Handle g_DHookOnRemoveHalloweenTiny;
Handle g_SDKCallGetBaseEntity;

ConVar g_TinyUnstuckAllowTeammates;

static Address g_offset_CTFPlayerShared_pOuter;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.halloween_tiny_unstuck");
	
	g_DHookOnRemoveHalloweenTiny =
			DHookCreateFromConf(hGameConf, "CTFPlayerShared::OnRemoveHalloweenTiny()");
	
	DHookEnableDetour(g_DHookOnRemoveHalloweenTiny, false, OnRemoveHalloweenTinyPre);
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseEntity::GetBaseEntity()");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_SDKCallGetBaseEntity = EndPrepSDKCall();
	
	g_offset_CTFPlayerShared_pOuter =
			view_as<Address>(GameConfGetOffset(hGameConf, "CTFPlayerShared::m_pOuter"));
	
	delete hGameConf;
	
	g_TinyUnstuckAllowTeammates = CreateConVar("sm_tf_tiny_unstuck_allow_teammates", "1",
			"Allow the unstuck routine to teleport players into their teammates.");
}

public MRESReturn OnRemoveHalloweenTinyPre(Address pPlayerShared) {
	Address pOuter = view_as<Address>(LoadFromAddress(
			pPlayerShared + g_offset_CTFPlayerShared_pOuter, NumberType_Int32));
	int client = GetEntityFromAddress(pOuter);
	
	float vecPosition[3], vecUnstuckPosition[3];
	GetClientAbsOrigin(client, vecPosition);
	
	if (FindValidTeleportDestination(client, vecPosition, vecUnstuckPosition)) {
		TeleportEntity(client, vecUnstuckPosition, NULL_VECTOR, NULL_VECTOR);
	}
	
	return MRES_Ignored;
}

/** 
 * Attempts to find a nearby position that a player can be teleported to without getting stuck.
 * The position is stored in vecDestination.
 * 
 * @return true if a space is found
 */
bool FindValidTeleportDestination(int client, const float vecPosition[3],
		float vecDestination[3]) {
	float vecMins[3], vecMaxs[3];
	GetEntPropVector(client, Prop_Send, "m_vecMinsPreScaled", vecMins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxsPreScaled", vecMaxs);
	
	Handle trace = TR_TraceHullFilterEx(vecPosition, vecPosition, vecMins, vecMaxs,
			MASK_PLAYERSOLID, TeleportTraceFilter, client);
	
	bool valid = !TR_DidHit(trace);
	delete trace;
	
	if (valid) {
		vecDestination = vecPosition;
		return true;
	}
	
	// Basic unstuck handling.
	/** 
	 * Basically we treat the corners and center edges of the player's bounding box as potential
	 * teleport destination candidates.
	 */
	float vecTestPosition[3];
	for (int z = 0; z < 2; z++) {
		float zpos;
		switch (z) {
			case 0: {
				zpos = 10.0;
			}
			case 1: {
				// less likely to hit the ceiling so do that second
				zpos = -vecMaxs[2];
			}
		}
		
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				float vecOffset[3];
				vecOffset[2] = zpos;
				
				switch (x) {
					case -1: { vecOffset[0] = vecMins[0]; }
					case 1: { vecOffset[0] = vecMaxs[0]; }
				}
				
				switch (y) {
					case -1: { vecOffset[1] = vecMins[1]; }
					case 1: { vecOffset[1] = vecMaxs[1]; }
				}
				
				AddVectors(vecPosition, vecOffset, vecTestPosition);
				
				trace = TR_TraceHullFilterEx(vecTestPosition, vecTestPosition, vecMins, vecMaxs,
						MASK_PLAYERSOLID, TeleportTraceFilter, client);
				
				valid = !TR_DidHit(trace);
				
				delete trace;
				
				if (valid) {
					vecDestination = vecTestPosition;
					return true;
				}
			}
		}
	}
	
	return false;
}

/** 
 * Return true if traced entity should prevent teleport to that position.
 */
public bool TeleportTraceFilter(int entity, int contents, int client) {
	// ignore world (hull should hit it anyways)
	if (entity <= 0) {
		return false;
	}
	
	// allow teleport to self
	if (client == entity) {
		return false;
	}
	
	// check if traced entity is a player and check for friendly unstuck
	if (entity < MaxClients
			&& g_TinyUnstuckAllowTeammates.BoolValue
			&& GetClientTeam(entity) == GetClientTeam(client)) {
		return false;
	}
	
	return true;
}

int GetEntityFromAddress(Address pEntity) {
	return SDKCall(g_SDKCallGetBaseEntity, pEntity);
}
