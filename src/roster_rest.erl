%%%----------------------------------------------------------------------
%%% File    : ejabberd_auth_rest.erl
%%% Author  : Pablo Polvorin <pablo.polvorin@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2015   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------

-module(roster_rest).
-behaviour(ejabberd_config).

-export([start/2, stop/1, get_user_roster/2,
	 get_jid_info/3, opt_type/1]).


-include("jlib.hrl").
-include("ejabberd.hrl").
-include("logger.hrl").
-include("mod_roster.hrl").

start(Host, _Opts) ->
    rest:start(Host),
    ok.

stop(_Host) ->
    ok.

get_jid_info(LServer, LUser, LJID) ->
    {ok, Roster} = get_user_roster(LServer, LUser),
    case lists:keyfind(LJID, #roster.jid, Roster) of
      false -> not_found;
      Item -> {ok, Item}
    end.

get_user_roster(Server, User) ->
    case rest:get(Server, path(Server), [{"username", User}]) of
        {ok, 200, JSon} -> json_to_rosteritems(Server, User, JSon);
        {ok, Code, JSon} -> {error, {Code, JSon}};
        {error, Reason} -> {error, Reason}
    end.

json_to_rosteritems(LServer, LUser, {[{<<"roster">>, Roster}]}) ->
    try lists:map(fun ({Fields}) ->
                          fields_to_roster(LServer, LUser, #roster{}, Fields)
                  end,
                  Roster)
    of
      Items -> {ok, Items}
    catch
      _:Error -> {error, {invalid_roster, Error}}
    end.

fields_to_roster(_LServer, _LUser, Item, []) -> Item;
fields_to_roster(LServer, LUser, Item,
                 [{<<"username">>, Username} | Rest]) ->
    case jlib:make_jid(Username, LServer, <<>>) of
        error ->
            ?ERROR_MSG("Invalid roster item for user ~s: username ~s", [LUser, Username]),
            fields_to_roster(LServer, LUser, Item, Rest);
        JID ->
            US = {LUser, LServer},
            USJ = {LUser, LServer, jlib:jid_tolower(JID)},
            USR = {JID#jid.user, JID#jid.server, JID#jid.resource},
            fields_to_roster(LServer, LUser,
                             Item#roster{usj = USJ, us = US, jid = USR}, Rest)
    end;
fields_to_roster(LServer, LUser, Item,
                 [{<<"jid">>, JidBin} | Rest]) ->
    case jlib:string_to_jid((JidBin)) of
        error ->
            ?ERROR_MSG("Invalid roster item for user ~s: jid ~s", [LUser, JidBin]),
            fields_to_roster(LServer, LUser, Item, Rest);
        JID ->
            US = {LUser, LServer},
            USJ = {LUser, LServer, jlib:jid_tolower(JID)},
            USR = {JID#jid.user, JID#jid.server, JID#jid.resource},
            fields_to_roster(LServer, LUser,
                             Item#roster{usj = USJ, us = US, jid = USR}, Rest)
    end;
fields_to_roster(LServer, LUser, Item,
                 [{<<"subscription">>, <<"both">>} | Rest]) ->
    fields_to_roster(LServer, LUser,
                     Item#roster{subscription = both}, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{<<"subscription">>, <<"from">>} | Rest]) ->
    fields_to_roster(LServer, LUser,
                     Item#roster{subscription = from}, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{<<"subscription">>, <<"to">>} | Rest]) ->
    fields_to_roster(LServer, LUser,
                     Item#roster{subscription = to}, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{<<"subscription">>, <<"none">>} | Rest]) ->
    fields_to_roster(LServer, LUser,
                     Item#roster{subscription = none}, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{<<"subscription">>, <<"remove">>} | Rest]) ->
    fields_to_roster(LServer, LUser,
                     Item#roster{subscription = remove}, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{<<"subscription">>, Sub} | Rest]) ->
    ?ERROR_MSG("Invalid roster item for user ~s: subscription ~s", [LUser, Sub]),
    fields_to_roster(LServer, LUser, Item, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{<<"nick">>, Nick} | Rest]) ->
    fields_to_roster(LServer, LUser,
                     Item#roster{name = (Nick)}, Rest);
fields_to_roster(LServer, LUser, Item,
                 [{Field, Value} | Rest]) ->
    ?ERROR_MSG("Invalid roster item for user ~s: unknown field ~s=~s", [LUser, Field, Value]),
    fields_to_roster(LServer, LUser, Item, Rest).
    %throw({unknown_field, {Field, Value}}).


%%%----------------------------------------------------------------------
%%% HTTP helpers
%%%----------------------------------------------------------------------

path(Server) ->
    ejabberd_config:get_option({ext_api_path_roster, Server},
			       fun(X) -> iolist_to_binary(X) end,
			       <<"/roster">>).

opt_type(ext_api_path_roster) ->
    fun (X) -> iolist_to_binary(X) end;
opt_type(_) -> [ext_api_path_roster].