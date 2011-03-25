%% - Server module
%% - The server module creates a parallel registered process by spawning a process which 
%% evaluates initialize(). 
%% The function initialize() does the following: 
%%      1/ It makes the current process as a system process in order to trap exit.
%%      2/ It creates a process evaluating the store_loop() function.
%%      4/ It executes the server_loop() function.

-module(server).

-export([start/0]).

%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start() -> 
    register(transaction_server, spawn(fun() ->
					       process_flag(trap_exit, true),
					       Val= (catch initialize()),
					       io:format("Server terminated with:~p~n",[Val])
				       end)).

initialize() ->
    process_flag(trap_exit, true),
    Initialvals = [{a,0},{b,0},{c,0},{d,0}], %% All variables are set to 0
    ServerPid = self(),
    StorePid = spawn_link(fun() -> store_loop(ServerPid,Initialvals) end),
    server_loop([],[],[],StorePid).
%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% - The server maintains a list of all connected clients and a store holding
%% the values of the global variable a, b, c and d 
server_loop(ClientList,LockList,WaitList,StorePid) ->
    receive
	{login, MM, Client} -> 
	    MM ! {ok, self()},
	    io:format("New client has joined the server:~p.~n", [Client]),
	    StorePid ! {print, self()},
	    server_loop(add_client({Client,[]},ClientList),LockList,WaitList,StorePid);
	{close, Client} -> 
	    io:format("Client~p has left the server.~n", [Client]),
	    StorePid ! {print, self()},
	    server_loop(remove_client(Client,ClientList),LockList,WaitList,StorePid);
	{request, Client} -> 
	    Client ! {proceed, self()},
	    server_loop(ClientList,LockList,WaitList,StorePid);
	{confirm, Client, PacketN} ->
		ClientWithActions = our_key_find(Client,1,ClientList),
		case PacketN - length(element(2,ClientWithActions)) of
			1 ->
				case lockList(ClientWithActions,LockList) of
					{false,NewLockList} ->
						server_loop(ClientList,NewLockList,WaitList ++ [ClientWithActions],StorePid);
					{true,NewLockList} ->
						Sp = self(),
						spawn(fun() -> do_actions(ClientWithActions,StorePid,Sp) end),
						server_loop(lists:keyreplace(Client,1,ClientList,{Client,[]}),NewLockList,WaitList,StorePid)
				end;
			_ ->
				Client ! {packetloss, self()},
				server_loop(ClientList,LockList,WaitList,StorePid)
		end;
	{committed, Client} ->
		Client ! {committed, self()},
		NewLockList = unlock(Client,LockList),
		server_loop(ClientList,NewLockList,excute_waiting_list(WaitList,NewLockList,StorePid),StorePid);
	{action, Client, Act, PacketN} ->
	    io:format("Received~p from client~p.~n", [Act, Client]),
		io:format("~p~n", [ClientList]),
		server_loop(add_action(Client,Act,ClientList,PacketN),LockList,WaitList,StorePid)
    after 50000 ->
		case all_gone(ClientList) of
	    	true -> exit(normal);   
	    	false -> server_loop(ClientList,LockList,WaitList,StorePid)
		end
    end.

%% - The values are maintained here
store_loop(ServerPid, Database) -> 
    receive
	{print, ServerPid} -> 
	    io:format("Database status:~n~p.~n",[Database]),
	    store_loop(ServerPid,Database);
	{read, Var, ActionPid} ->
	    io:format("Reading...~n"),
	    ActionPid ! {read_response,do_read(Var, Database)},
	    store_loop(ServerPid,Database);
	{write, Var, Val, ActionPid} ->
	    io:format("Writing...~n"),
	    NewDatabase = do_write(Var, Val, Database),
	    ActionPid ! {write_confirm, self()},
	    store_loop(ServerPid,NewDatabase);
	X ->
	    io:format("Database received unknown operator.~p~n", [X]),
	    store_loop(ServerPid,Database)
    end.
%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% - Low level function to handle lists
add_client(C,T) -> [C|T].

add_action(_,_,[],_) -> [];
add_action(C,A,[{C,AL}|T],PacketN) ->
		[{C,add_action_to_client(AL, A, PacketN, 1)}|T];
add_action(C,A,[H|T],PacketN) ->
	[H|add_action(C,A,T,PacketN)].

add_action_to_client([], Action, PacketN, PacketN) -> [{Action,PacketN}];
add_action_to_client([], Action,PacketN,_) -> [{Action,PacketN}];
add_action_to_client([{Action,PacketN}|T], Action, PacketN, PacketN) -> [{Action,PacketN}|T];
add_action_to_client([{Action,PacketN}|T], Action, PacketN, _) -> [{Action,PacketN}|T];
add_action_to_client(AL,Action,PacketN,PacketN) -> [{Action,PacketN}|AL];
add_action_to_client([{Action,PacketN}|T], NewAction, NewPacketN, Counter) ->
	case PacketN > NewPacketN of
		true ->
			[{NewAction,NewPacketN}|[{Action,PacketN}|T]];
		false ->
			[{Action,PacketN}|add_action_to_client(T,NewAction,NewPacketN,Counter+1)]
	end.
	

lockList({_,[]},LockList) -> {true, LockList};
lockList({Client,[H|T]},LockList) ->
	case lock({Client,element(2,H)},LockList) of
		true ->
			lockList({Client,T},LockList);	
		false ->
			{false, element(2, lockList({Client,T},LockList))};
		X ->
			lockList({Client,T},X)
	end.

our_key_find(_,_,[]) -> false;
our_key_find(Key,N,[H|T]) ->
	case element(N,H) of
		Key ->
			H;
		_ ->
			our_key_find(Key,N,T)
	end.

lock(Var,LockList) ->
	case our_key_find(element(2,Var),2,LockList) of
	false ->
		[Var|LockList];
	Var ->
		true;
	_ ->
		false
	end.

unlock(Client,LockList) ->
	lists:filter(
		(fun({X,_}) -> 
			case X of
				Client ->
					false;
				_ ->
					true
			end
		end),LockList).

excute_waiting_list([],_,_) -> [];
excute_waiting_list([H|T],LockList,StorePid) ->
	case lockList(H,LockList) of
		{false,NewLockList} ->
			[H|excute_waiting_list(T,NewLockList,StorePid)];
		{true,NewLockList} ->
			spawn(server, do_actions(H,StorePid,self())),
			excute_waiting_list(T,NewLockList,StorePid)
	end.

do_actions({Client,[]},_,ServerPid) ->
    ServerPid ! {committed, Client};
do_actions({Client,[{H,PacketN}|T]},StorePid,ServerPid) ->
	io:format("Executes action ~p, with packet number ~p~n",[H,PacketN]),
    case H of
	{read,Var} ->
	    StorePid ! {read,Var,self()},
	    receive
		{read_response,Answer} ->
		    io:format("Read response: ~p~n", [Answer])
	    end;
	{write,Var,Val} ->
	    StorePid ! {write,Var,Val,self()},
		receive
		{write_confirm,Pid} ->
		    io:format("Write response from: ~p~n", [Pid])
	    end;
	X ->
	    io:format("Wrong in do_actions! ~p~n",[X])
    end,
	do_actions({Client,T},StorePid,ServerPid).

do_read(_,[]) ->
    io:format("Wrong in do_read!");
do_read(Var,[{Var,Val}|_]) ->
    Val;
do_read(Var,[_|T]) ->
    do_read(Var,T).

do_write(_,_,[]) ->
    io:format("Wrong in do_write!");
do_write(Var,NewVal,[{Var,_}|T]) ->
    [{Var,NewVal}|T];
do_write(Var,NewVal,[H|T]) ->
    [H|do_write(Var,NewVal,T)].

remove_client(_,[]) -> [];
remove_client(C, [{C,_}|T]) -> T;
remove_client(C, [H|T]) -> [H|remove_client(C,T)].

all_gone([]) -> true;
all_gone(_) -> false.
