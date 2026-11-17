-- Sets the nicky role's password from the psql variable `pw`.
--
-- Fed to psql with `-f` (see services/postgresql.nix): variables are expanded
-- in a script file, but NOT in `-c`, which would send this verbatim and fail.
-- `:'pw'` makes psql quote the value as a SQL literal, so the password can
-- contain quotes, spaces or semicolons safely, and it never appears in the
-- process list.
ALTER ROLE nicky PASSWORD :'pw';
