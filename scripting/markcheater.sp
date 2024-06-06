#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <regex>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
    name = "[TF2] Mark Cheaters", 
    author = "ampere", 
    description = "Cheater marker to troll them.", 
    version = "1.4", 
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
    RegAdminCmd("sm_marked", CMD_Marked, ADMFLAG_GENERIC);
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
        ReplyToCommand(client, "[SM] Usage: sm_mark <#userid|name|STEAMID2>");
        return Plugin_Handled;
    }
    
    bool isSteamid;
    char arg1[32];
    GetCmdArg(1, arg1, sizeof(arg1));
    char steamid[32];
    int target;

    if (SimpleRegexMatch(arg1, "STEAM_[10]:[10]:[0-9]+"))
    {
        for (int i = 0; i < g_Marked.Length; i++)
        {
            char sid[32];
            GetClientAuthId(GetClientOfUserId(g_Marked.Get(i)), AuthId_Steam2, sid, sizeof(sid));
            if (!strcmp(arg1, sid))
            {
                ReplyToCommand(client, "[SM] This player has already been marked!");
                return Plugin_Handled;
            }
        }
        steamid = arg1;
        isSteamid = true;
    }
    else
    {
        target = FindTarget(client, arg1);
        
        if (target == -1)
        {
            return Plugin_Handled;
        }

        int userid = GetClientUserId(target);
        if (g_Marked.FindValue(userid) != -1)
        {
            ReplyToCommand(client, "[SM] This player has already been marked!");
            return Plugin_Handled;
        }
        GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
    }
    
    char query[128];
    g_DB.Format(query, sizeof(query), "INSERT INTO markedplayers (steamid) VALUES ('%s')", steamid);
    
    DataPack pack = new DataPack();
    if (client != 0)
    {
        pack.WriteCell(GetClientUserId(client));
    }
    else
    {
        pack.WriteCell(0);
    }
    pack.WriteCell(target ? GetClientUserId(target) : 0);
    pack.WriteCell(isSteamid);
    pack.WriteString(steamid);
    g_DB.Query(OnMarkedPlayer, query, pack);
    return Plugin_Handled;
}

public void OnMarkedPlayer(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    if (error[0] != '\0')
    {
        PrintToServer(error);
        return;
    }

    pack.Reset();
    int client = pack.ReadCell();
    int target = GetClientOfUserId(pack.ReadCell());
    bool isSteamid = pack.ReadCell();
    if (isSteamid)
    {
        char steamid[32];
        pack.ReadString(steamid, sizeof(steamid));
        if (client == 0)
        {
            PrintToServer("[SM] The specified Steam ID (%s) has been marked.", steamid);
        }
        else
        {
            PrintToChat(GetClientOfUserId(client), "[SM] The specified Steam ID (%s) has been marked.", steamid);
        }

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientConnected(i))
            {
                return;
            }
            
            char sid[32];
            GetClientAuthId(i, AuthId_Steam2, sid, sizeof(sid));
            if (!strcmp(steamid, sid))
            {
                g_Marked.Push(GetClientUserId(i));
                if (client == 0)
                {
                    PrintToServer("[SM] The user (%N) has been found inside the server, marking...", i);
                }
                else
                {
                    PrintToChat(GetClientOfUserId(client), "[SM] The user (%N) has been found inside the server, marking...", i);
                }
            }
        }
        return;
    }

    delete pack;
    
    g_Marked.Push(GetClientUserId(target));
    if (client == 0)
    {
        PrintToServer("[SM] %N has been marked as cheater.", target);
    }
    else
    {
        PrintToChat(GetClientOfUserId(client), "[SM] %N has been marked as cheater.", target);
    }
}

public Action CMD_Unmark(int client, int args)
{
    if (args != 1)
    {
        ReplyToCommand(client, "[SM] Usage: sm_unmark <#userid|name|STEAMID2>");
        return Plugin_Handled;
    }
    
    bool isSteamid;
    char arg1[32];
    GetCmdArg(1, arg1, sizeof(arg1));
    char steamid[32];
    int target;

    if (SimpleRegexMatch(arg1, "STEAM_[10]:[10]:[0-9]+"))
    {
        bool found = false;
        for (int i = 0; i < g_Marked.Length; i++)
        {
            char sid[32];
            GetClientAuthId(GetClientOfUserId(g_Marked.Get(i)), AuthId_Steam2, sid, sizeof(sid));
            if (!strcmp(arg1, sid))
            {
                found = true;
            }
        }
        if (!found)
        {
            ReplyToCommand(client, "[SM] This player was not marked!");
            return Plugin_Handled;
        }
        steamid = arg1;
        isSteamid = true;
    }
    else
    {
        target = FindTarget(client, arg1);
        
        if (target == -1)
        {
            return Plugin_Handled;
        }

        int userid = GetClientUserId(target);
        if (g_Marked.FindValue(userid) == -1)
        {
            ReplyToCommand(client, "[SM] This player was not marked!");
            return Plugin_Handled;
        }
        GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
    }
    
    char query[128];
    g_DB.Format(query, sizeof(query), "DELETE FROM markedplayers WHERE steamid = '%s'", steamid);
    
    DataPack pack = new DataPack();
    if (client != 0)
    {
        pack.WriteCell(GetClientUserId(client));
    }
    else
    {
        pack.WriteCell(0);
    }
    pack.WriteCell(target ? GetClientUserId(target) : 0);
    pack.WriteCell(isSteamid);
    pack.WriteString(steamid);
    g_DB.Query(OnUnmarkedPlayer, query, pack);
    return Plugin_Handled;
}

public void OnUnmarkedPlayer(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    if (error[0] != '\0')
    {
        PrintToServer(error);
        return;
    }

    pack.Reset();
    int client = pack.ReadCell();
    int target = GetClientOfUserId(pack.ReadCell());
    bool isSteamid = pack.ReadCell();
    if (isSteamid)
    {
        char steamid[32];
        pack.ReadString(steamid, sizeof(steamid));
        if (client == 0)
        {
            PrintToServer("[SM] The specified Steam ID (%s) has been unmarked.", steamid);
        }
        else
        {
            PrintToChat(GetClientOfUserId(client), "[SM] The specified Steam ID (%s) has been unmarked.", steamid);
        }

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientConnected(i))
            {
                return;
            }

            char sid[32];
            GetClientAuthId(i, AuthId_Steam2, sid, sizeof(sid));
            if (StrEqual(steamid, sid) && g_Marked.FindValue(GetClientUserId(i)) != -1)
            {
                g_Marked.Erase(g_Marked.FindValue(GetClientUserId(i)));
                if (client == 0)
                {
                    PrintToServer("[SM] The user (%N) has been found inside the server, unmarking...", i);
                }
                else
                {
                    PrintToChat(GetClientOfUserId(client), "[SM] The user (%N) has been found inside the server, unmarking...", i);
                }
            }
        }
        return;
    }

    delete pack;
    
    g_Marked.Erase(g_Marked.FindValue(GetClientUserId(target)));
    if (client == 0)
    {
        PrintToServer("[SM] %N has been unmarked!", target);
    }
    else
    {
        PrintToChat(GetClientOfUserId(client), "[SM] %N has been unmarked!", target);
    }
}

public Action CMD_Marked(int client, int args)
{
    char query[256];
    g_DB.Format(query, sizeof(query), "SELECT * FROM markedplayers");
    g_DB.Query(OnMarkedPlayersReceived, query, client ? GetClientUserId(client) : 0);
    return Plugin_Handled;
}

public void OnMarkedPlayersReceived(Database db, DBResultSet results, const char[] error, int userid)
{
    if (error[0] != '\0') 
    {
        char error2[128];
        Format(error2, sizeof(error2), "[SM] Failed to receive players! %s", error);
        if (!userid)
        {
            PrintToServer(error2);
        }
        else
        {
            PrintToChat(GetClientOfUserId(userid), error2);
        }
        return;
    }

    int client = userid ? GetClientOfUserId(userid) : 0;


    if (!client)
    {
        char chatMessage[1024];
        if (g_Marked.Length > 0)
        {
            chatMessage = "[SM] In-game marked players:\n";
            for(int i = 0; i < g_Marked.Length; i++)
            {
                char buf[32];
                Format(buf, sizeof(buf), "  - %N\n", GetClientOfUserId(g_Marked.Get(i)));
                StrCat(chatMessage, sizeof(chatMessage), buf);
            }
        }
        else
        {
            chatMessage = "[SM] No in-game marked players.";
        }

        PrintToServer(chatMessage);
    }

    Menu menu = new Menu(MenuHandler_MarkedPlayers);
    menu.SetTitle("Marked Players");

    while (results.FetchRow())
    {
        char entry[64];
        results.FetchString(0, entry, sizeof(entry));

        for(int i = 0; i < g_Marked.Length; i++)
        {
            char steamid[32];
            GetClientAuthId(GetClientOfUserId(g_Marked.Get(i)), AuthId_Steam2, steamid, sizeof(steamid));
            if (!strcmp(entry, steamid))
            {
                char buf[32];
                Format(buf, sizeof(buf), " (%N)", GetClientOfUserId(g_Marked.Get(i)));
                StrCat(entry, sizeof(entry), buf);
            }
        }

        menu.AddItem(entry, entry);
    }

    if (menu.ItemCount == 0) 
    {
        menu.AddItem("0", "No marked players found");
    }

    menu.Display(client, 20);
}

public int MenuHandler_MarkedPlayers(Menu menu, MenuAction action, int client, int param)
{
    return 0;
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