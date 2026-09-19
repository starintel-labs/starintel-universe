% Release policy: when may a universe revision be released?
%
% A release requires (facts recorded by CI):
%   * the revision's universe-level checks green
%   * the packaging artifacts recorded with digests
%   * the exact component pins recorded (manifest completeness)
%   * no uncommitted drift between recorded pins and the registry

release_artifacts(
    [ iso_x86_64
    , vanta_deb
    , vanta_rpm
    , vanta_arch
    , starintel_deb
    , starintel_rpm
    , starintel_arch
    ]).

all_components_pinned :-
    forall(component(C), ( pin(C, Sha, _), sha_atom(Sha) )).

sha_atom(S) :- atom(S), atom_length(S, 40).

release_artifacts_recorded :-
    release_artifacts(As),
    member(A, As),
    \+ artifact(A, _, _),
    throw(error(policy_missing_artifact(A), _)).
release_artifacts_recorded :- !.
release_artifacts_recorded.

manifest_complete :-
    all_components_pinned,
    artifact(manifest, _, _).

release_allowed(universe) :-
    all_required_checks_green(universe),
    manifest_complete,
    release_artifacts_recorded.

release_denial(Reasons) :-
    findall(R, release_denial_reason(R), Reasons).

release_denial_reason(checks_not_green(C, Status)) :-
    required_check(universe, C),
    catch(check_status(C, Status), _, Status = missing),
    Status \= green.
release_denial_reason(component_unpinned(C)) :-
    component(C),
    \+ pin(C, _, _).
release_denial_reason(manifest_missing) :-
    \+ artifact(manifest, _, _).
release_denial_reason(artifact_missing(A)) :-
    release_artifacts(As),
    member(A, As),
    \+ artifact(A, _, _).
