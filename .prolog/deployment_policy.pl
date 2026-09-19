% Deployment policy: stage transitions.
%
% candidate -> integration -> staging -> release
%
% deployment_allowed(+FromStage, +ToStage) is det and total for the
% canonical chain; skipping stages is denied. Deployments must name the
% exact universe revision they deploy (deployed_revision/1 fact written by
% the deployment runner).

stage(candidate).
stage(integration).
stage(staging).
stage(release).

stage_rank(candidate,   1).
stage_rank(integration, 2).
stage_rank(staging,     3).
stage_rank(release,     4).

deployment_allowed(From, To) :-
    stage(From),
    stage(To),
    stage_rank(To, RTo),
    stage_rank(From, RFrom),
    RTo is RFrom + 1.

staging_allowed(Revision) :-
    stage_rank(integration, 2),
    deployed_revision(integration, Revision),
    all_required_checks_green(universe),
    revision_note(Revision, note(staging_smoke_green)).

production_allowed(Revision) :-
    deployed_revision(staging, Revision),
    staging_allowed(Revision),
    release_allowed(universe).

% No deployment from mutable component heads: the deployed revision must
% be an exact universe commit recorded in facts.
deployed_revision(Stage, Revision) :-
    stage(Stage),
    revision_note(universe, note(deployed(Stage, Revision))).
