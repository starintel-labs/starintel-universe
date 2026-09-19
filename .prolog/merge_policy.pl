% Merge policy: when may a candidate change merge into the universe?
%
% Facts (machine-generated): check(Name, Status) with Status in
% {green, red, skipped, pending}. Required checks are declared here.

required_check(universe, unit).
required_check(universe, integration).
required_check(universe, actor_matrix).
required_check(universe, quasar_e2e).
required_check(universe, replay).
required_check(universe, packaging).

% Per-component re-validation required when that component changes.
required_for_change(Component, Check) :-
    component_check(Component, Check).

component_check(starintel_server, server_unit).
component_check(starintel_server, server_integration).
component_check(quasar,         quasar_native).
component_check(quasar_ui,      quasar_ui_native).
component_check(star_lang,      star_lang_native).
component_check(star_kb,        star_kb_native).
component_check(star_cl,        star_cl_native).
component_check(prolog_rlm,     prolog_rlm_native).
component_check(zara,           vanta_native).
component_check(vanta,          vanta_native).
component_check(zara_plugins,   zara_plugins_native).
component_check(dotfiles,       dotfiles_homes).

check_status(Name, green) :-
    check(Name, green), !.
check_status(Name, Status) :-
    check(Name, Status), !.
check_status(Name, unknown) :-
    \+ check(Name, _),
    format(atom(Msg), "required check ~w has no recorded status", [Name]),
    throw(error(policy_missing_fact(Msg), _)).

all_required_checks_green(universe) :-
    forall(required_check(universe, C), check_status(C, green)).

component_checks_green(Component) :-
    forall(required_for_change(Component, C), check_status(C, green)).

% merge_allowed(+ChangeSet): the gate. Deterministic. Succeeds only when
%   * every candidate is admissible (update policy)
%   * the dependency closure is valid for the batch
%   * all universe-level required checks are green
%   * every changed component's native checks are green
merge_allowed(ChangeSet) :-
    candidate_set_allowed(ChangeSet),
    dependency_closure_valid(ChangeSet),
    all_required_checks_green(universe),
    changed_components(ChangeSet, Changed),
    maplist(component_checks_green, Changed).

% merge_denial(+ChangeSet, -Reasons): explanation interface for CI.
merge_denial(ChangeSet, Reasons) :-
    findall(Reason,
            merge_denial_reason(ChangeSet, Reason),
            Reasons).

merge_denial_reason(ChangeSet, candidate_rejected(c(C, From, To))) :-
    member(c(C, From, To), ChangeSet),
    \+ catch(candidate_allowed(C, From, To), _, fail).
merge_denial_reason(ChangeSet, closure_invalid) :-
    \+ catch(dependency_closure_valid(ChangeSet), _, fail).
merge_denial_reason(_, required_check_not_green(C, Status)) :-
    required_check(universe, C),
    catch(check_status(C, Status), _, Status = missing),
    Status \= green.
merge_denial_reason(ChangeSet, component_check_not_green(C, Status)) :-
    changed_components(ChangeSet, Changed),
    member(C, Changed),
    required_for_change(C, Check),
    catch(check_status(Check, Status), _, Status = missing),
    Status \= green.
