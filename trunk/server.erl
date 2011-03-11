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
    server_loop([],[],StorePid).
%%%%%%%%%%%%%%%%%%%%%%% STARTING SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% - The server maintains a list of all connected clients and a store holding
%% the values of the global variable a, b, c and d 
server_loop(ClientList,LockList,StorePid) ->
    receive
	{login, MM, Client} -> 
	    MM ! {ok, self()},
	    io:format("New client has joined the server:~p.~n", [Client]),
	    StorePid ! {print, self()},
	    server_loop(add_client({Client,[]},ClientList),LockList,StorePid);
	{close, Client} -> 
	    io:format("Client~p has left the server.~n", [Client]),
	    StorePid ! {print, self()},
	    server_loop(remove_client(Client,ClientList),LockList,StorePid);
	{request, Client} -> 
	    Client ! {proceed, self()},
	    server_loop(ClientList,LockList,StorePid);
	{confirm, Client} ->
		ClientWithActions = lists:keyfind(Client,1,ClientList)
		case lockList(ClientWithActions,LockList) of
			{false,NewLockList} ->
				WaitList ++ [ClientWithActions],
				server_loop(ClientList,NewLockList,StorePid);
			{true,NewLockList} ->
				spawn(server, do_actions(),[ClientWithActions,StorePid,self()]),
				server_loop(lists:keyreplace(Client,1,ClientList,{Client,[]}),NewLockList,StorePid); 		
	{committed, Client} ->
		Client ! {committed, self()},
		unlock(Client,LockList);
	{action, Client, Act} ->
	    io:format("Received~p from client~p.~n", [Act, Client]),
		io:format("~p~n", [ClientList]),
	    server_loop(add_action(Client,Act,ClientList),LockList,StorePid)
    after 50000 ->
	case all_gone(ClientList) of
	    true -> exit(normal);    
	    false -> server_loop(ClientList,LockList,StorePid)
	end
    end.

%% - The values are maintained here
store_loop(ServerPid, Database) -> 
    receive
	{print, ServerPid} -> 
	    io:format("Database status:~n~p.~n",[Database]),
	    store_loop(ServerPid,Database);
	{read, Var} ->
	    io:format("Read action.~n"),
	    ServerPid ! {read_response,do_read(Var, Database)},
	    store_loop(ServerPid,Database);
	{write, Var, Val} ->
	    io:format("Write action.~n"),
	    NewDatabase = do_write(Var, Val, Database),
	    ServerPid ! {write_confirm, self()},
	    store_loop(ServerPid,NewDatabase);
	X ->
	    io:format("Database received unknown operator.~p~n", [X]),
	    store_loop(ServerPid,Database)
    end.
%%%%%%%%%%%%%%%%%%%%%%% ACTIVE SERVER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% - Low level function to handle lists
add_client(C,T) -> [C|T].

add_action(_,_,[]) -> [];
add_action(C,A,[{C,AL}|T]) -> [{C,AL ++ [A]}|T];
add_action(C,A,[H|T]) -> [H|add_action(C,A,T)].

lockList({Client,[]},LockList) -> LockList;
lockList({Client,[H|T]},LockList) ->
	case lock({Client,element(2,H)},LockList) of
		true ->
			lockList({Client,T},LockList);
		false ->
			lockList({Client,T},LockList),
			false;
		X ->
			lockList({Client,T},X)
	end.

lock(Var,LockList) ->
	case lists:keyfind(Var,2,LockList) of
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

do_actions({Client,[]},_,ServerPid) -> 
    ServerPid ! {committed, Client};
do_actions({Client,[H|T]},StorePid,ServerPid) ->
    case H of
	{read,Var} ->
	    StorePid ! {read,Var},
	    receive
		{read_response,Answer} ->
		    io:format("Read response: ~p~n", [Answer])
	    end;
	{write,Var,Val} ->
	    StorePid ! {write,Var,Val};
	X ->
	    io:format("Wrong in do_actions! ~p~n",[X])
    end
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
