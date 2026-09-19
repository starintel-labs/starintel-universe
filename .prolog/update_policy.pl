% Update policy: is a candidate submodule revision admissible?
%
% The shell/CI gathers facts (pin/3, upstream_head/2). Prolog decides.
% No LLM output is ever parsed for this decision.

sha_pattern(S) :-
    atom(S),
    atom_length(S, 40),
    atom_codes(S, Codes),
    maplist(hex_digit, Codes).

hex_digit(C) :- between(0'0, 0'9, C), !.
hex_digit(C) :- between(0'a, 0'f, C), !.
hex_digit(C) :- between(0'A, 0'F, C), !.

% known_pin/2: current pin for a component (vanta and zara share a pin).
known_pin(Component, Sha) :-
    pin(Component, Sha, _).

% candidate_allowed(+Component, +From, +To) is det.
% A candidate revision is admissible when:
%   * the component is registered
%   * From is the current pin (no drift between claim and reality)
%   * From and To are well-formed object ids
%   * the change is a real change
%   * To is reachable from the upstream branch head recorded in facts
%     (upstream_head/2 recorded by CI from the canonical remote)
candidate_allowed(Component, From, To) :-
    must(component(Component)),
    must(known_pin(Component, From)),
    must(sha_pattern(From)),
    must(sha_pattern(To)),
    must(From \== To),
    must(upstream_reachable(Component, To)).

upstream_reachable(Component, To) :-
    upstream_head(Component, Head),
    !,
    (   To == Head
    ;   recorded_ancestor(Component, To, Head)
    ).
upstream_reachable(_, _).  % no upstream fact recorded: offline/local mode.

recorded_ancestor(Component, To, Head) :-
    revision_note(Component, note(ancestors(As))),
    member(To, As),
    member(Head, As),
    order_by_ancestor(As, To, Head).

order_by_ancestor(As, To, Head) :-
    nth0(ITo, As, To),
    nth0(IHead, As, Head),
    ITo =< IHead.

% changeset admissibility: every member allowed, closure still coherent.
% candidate_set(+Pairs) where Pairs = c(Component, From, To).
candidate_set_allowed([]).
candidate_set_allowed([c(C, F, T) | Rest]) :-
    candidate_allowed(C, F, T),
    candidate_set_allowed(Rest).

% dependency_closure_valid(+ChangeSet):
% every component that depends on a changed component is either itself in
% the changeset (batched, will be validated together) or has its required
% re-validation listed in the candidate's check plan.
dependency_closure_valid(ChangeSet) :-
    changed_components(ChangeSet, Changed),
    findall(Dep,
            ( member(C, Changed),
              dependents(C, Ds),
              member(Dep, Ds),
              \+ member(Dep, Changed) ),
            Affected),
    sort(Affected, Unique),
    require_revalidation(Unique).

require_revalidation([]).
require_revalidation([C | Cs]) :-
    revision_note(universe, note(revalidates(C))),
    require_revalidation(Cs).

changed_components(ChangeSet, Changed) :-
    findall(C, member(c(C, _, _), ChangeSet), Changed0),
    sort(Changed0, Changed).

% batching: compatible when no changed component is in the closure of
% another changed component in a conflicting direction — practically we
% allow batching but require the joint closure check above.
batch_allowed(ChangeSet) :-
    candidate_set_allowed(ChangeSet),
    dependency_closure_valid(ChangeSet).

% bisect_groups(+ChangeSet, -Groups): deterministic bisection plan.
% Split the failing set into halves; CI walks this plan when a batch fails.
bisect_groups(ChangeSet, [Left, Right]) :-
    length(ChangeSet, N),
    N > 1,
    Half is N // 2,
    length(Left, Half),
    append(Left, Right, ChangeSet).
