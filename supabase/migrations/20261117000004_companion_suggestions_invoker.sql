-- =============================================================================
-- MyPlaces – 14 (17/11/2026): list_companion_suggestions() -> SECURITY INVOKER
-- Security advisor (lint 0029) flagged the new function as a SECURITY DEFINER RPC. It does not need
-- elevated rights: every table it reads (places/visits/journals, *_members, visit_participants,
-- profiles) is already readable by the caller through RLS for exactly the rows it uses, so running it
-- with the caller's privileges returns the same result with one less privileged entry point.
-- my_timeline() stays SECURITY DEFINER on purpose: a Visit member cannot read public.places via RLS
-- (ERD-03 / places RLS is not widened), so the minimal Place projection needs the definer path.
-- =============================================================================
alter function public.list_companion_suggestions(text, integer) security invoker;
