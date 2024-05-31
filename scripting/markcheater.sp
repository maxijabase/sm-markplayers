#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "[TF2] Mark Cheaters", 
	author = "ampere", 
	description = "Cheater marker to troll them.", 
	version = "1.2", 
	url = "github.com/maxijabase"
};

ArrayList g_Marked;
bool g_Late;
Database g_DB;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Late = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegAdminCmd("sm_mark", CMD_Mark, ADMFLAG_GENERIC);
	RegAdminCmd("sm_unmark", CMD_Unmark, ADMFLAG_GENERIC);
	g_Marked = new ArrayList(ByteCountToCells(32));
	LoadTranslations("common.phrases");
	Database.Connect(OnDatabaseConnected, "storage-local");
}

public void OnClientPostAdminCheck(int client)
{
	if (g_DB == null)
	{
		return;
	}
	
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	char query[128];
	g_DB.Format(query, sizeof(query), "SELECT steamid FROM markedplayers WHERE steamid = '%s'", steamid);
	g_DB.Query(OnPlayerReceived, query, GetClientUserId(client));
}

public void OnPlayerReceived(Database db, DBResultSet results, const char[] error, int userid)
{
	if (error[0] != '\0')
	{
		PrintToServer(error);
		return;
	}
	
	if (results.RowCount > 0)
	{
		g_Marked.Push(userid);
		PrintToServer("[SM] %N was found in the marked database. Marking...", GetClientOfUserId(userid));
	}
}

public void OnDatabaseConnected(Database db, const char[] error, any data)
{
	g_DB = db;
	PrintToServer("[SM] Mark cheaters - connected to database.");
	g_DB.Query(OnTablesCreated, "CREATE TABLE IF NOT EXISTS markedplayers (steamid TEXT PRIMARY KEY);");
}

public void OnTablesCreated(Database db, DBResultSet results, const char[] error, any data)
{
	PrintToServer("[SM] Mark cheaters - tables created.");
	if (g_Late)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				OnClientPostAdminCheck(i);
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	int found = g_Marked.FindValue(GetClientUserId(client));
	if (found != -1)
	{
		g_Marked.Erase(found);
	}
}

public Action CMD_Mark(int client, int args)
{
	if (args != 1)
	{
		return Plugin_Handled;
	}
	
	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	int target = FindTarget(client, arg1);
	
	if (target == -1)
	{
		return Plugin_Handled;
	}
	
	int userid = GetClientUserId(target);
	if (g_Marked.FindValue(userid) != -1)
	{
		ReplyToCommand(client, "[SM] This player has already been marked!");
	}
	else
	{
		char steamid[32];
		GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
		char query[128];
		g_DB.Format(query, sizeof(query), "INSERT INTO markedplayers (steamid) VALUES ('%s')", steamid);
		
		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(GetClientUserId(target));
		
		g_DB.Query(OnMarkedPlayer, query, pack);
	}
	return Plugin_Handled;
}

public void OnMarkedPlayer(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int target = GetClientOfUserId(pack.ReadCell());
	delete pack;
	
	if (error[0] != '\0')
	{
		PrintToServer(error);
		return;
	}
	
	g_Marked.Push(GetClientUserId(target));
	PrintToChat(client, "[SM] %N has been marked as cheater.", target);
}

public Action CMD_Unmark(int client, int args)
{
	if (args != 1)
	{
		return Plugin_Handled;
	}
	
	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	int target = FindTarget(client, arg1);
	
	if (target == -1)
	{
		return Plugin_Handled;
	}
	
	int userid = GetClientUserId(target);
	int found = g_Marked.FindValue(userid);
	if (found != -1)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(found);
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(GetClientUserId(target));
		
		char steamid[32];
		GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
		char query[128];
		g_DB.Format(query, sizeof(query), "DELETE FROM markedplayers WHERE steamid = '%s'", steamid);
		g_DB.Query(OnUnmarkedPlayer, query, pack);
	}
	else {
		ReplyToCommand(client, "[SM] This player was not marked!");
	}
	return Plugin_Handled;
}

public void OnUnmarkedPlayer(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	int found = pack.ReadCell();
	int client = GetClientOfUserId(pack.ReadCell());
	int target = GetClientOfUserId(pack.ReadCell());
	delete pack;
	
	if (error[0] != '\0')
	{
		PrintToServer(error);
		return;
	}
	
	g_Marked.Erase(found);
	PrintToChat(client, "[SM] %N has been unmarked.", target);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (victim == attacker || attacker == 0)
	{
		return Plugin_Continue;
	}
	
	int attackerUserId = GetClientUserId(attacker);
	if (g_Marked.FindValue(attackerUserId) != -1)
	{
		
		int victimHealth = GetClientHealth(victim);
		int victimMaxHealth = GetEntProp(victim, Prop_Data, "m_iMaxHealth");
		if (victimHealth < victimMaxHealth * 1.5)
		{
			SetEntityHealth(victim, victimHealth + 5);
		}
		damage = 0.0;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
} 