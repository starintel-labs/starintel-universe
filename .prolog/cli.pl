% CLI bridge for the control plane: the shell, CI, and the
% universe-manager actor call this. Exit codes:
%   0 — policy decision is YES
%   1 — policy decision is NO
%   2 — usage / policy error (missing facts, bad terms)
%
% Usage:
%   swipl -q .prolog/cli.pl <command> [args...]
%
% Commands:
%   pins                       print current pins as c(Component,Sha,Branch)
%   candidate C From To        admissibility of one candidate
%   merge_allowed Terms        Terms = [c(C1,F1,T1),...]
%   merge_denial Terms         print denial reasons (exit reflects emptiness)
%   release_allowed
%   staging_allowed Rev
%   deployment_allowed From To

:- ensure_loaded(universe).

usage :-
    format(user_error, "usage: cli.pl <pins|candidate C F T|merge_allowed Terms|merge_denial Terms|release_allowed|staging_allowed Rev|deployment_allowed From To>~n", []),
    halt(2).

run([pins]) :- !,
    load_facts,
    (   pin(C, S, B),
        format("pin(~q, ~q, ~q).~n", [C, S, B]),
        fail
    ;   halt(0)
    ).

run([candidate, C, F, T]) :- !,
    load_facts,
    atom_to_term(C, CA, _),
    atom_to_term(F, FA, _),
    atom_to_term(T, TA, _),
    decide(candidate_allowed(CA, FA, TA)).

run([merge_allowed, Terms]) :- !,
    load_facts,
    atom_to_term(Terms, TermList, _),
    is_list(TermList),
    !,
    decide(merge_allowed(TermList)).
run([merge_allowed, _]) :- !,
    usage.

run([merge_denial, Terms]) :- !,
    load_facts,
    atom_to_term(Terms, TermList, _),
    (   merge_denial(TermList, Reasons)
    ->  (   Reasons == []
        ->  format("NO DENIALS~n"),
            halt(0)
        ;   maplist(print_reason, Reasons),
            halt(1)
        )
    ;   format("DENIED (unexplained)~n"),
        halt(1)
    ).

run([release_allowed]) :- !,
    load_facts,
    decide(release_allowed(universe)).

run([staging_allowed, Rev]) :- !,
    load_facts,
    atom_to_term(Rev, RA, _),
    decide(staging_allowed(RA)).

run([deployment_allowed, From, To]) :- !,
    load_facts,
    atom_to_term(From, FA, _),
    atom_to_term(To, TA, _),
    decide(deployment_allowed(FA, TA)).

run(_) :-
    usage.

print_reason(R) :-
    format("~q~n", [R]).

decide(Goal) :-
    (   catch(Goal, E, true)
    ->  (   var(E)
        ->  halt(0)
        ;   print_message(error, E),
            halt(2)
        )
    ;   halt(1)
    ).

:- prolog_load_context(directory, Dir),
   working_directory(_, Dir),
   current_prolog_flag(argv, Argv),
   run(Argv).
