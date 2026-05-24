# ❌ Error: System "mud" not found

## The Problem

When you run:
```lisp
(ql:quickload :mud)
```

You get:
```
debugger invoked on a QUICKLISP-CLIENT:SYSTEM-NOT-FOUND
  System "mud" not found
```

## The Cause

Quicklisp (and ASDF) doesn't know where your `mud.asd` file is located. By default, they only look in:
- Quicklisp's local-projects directory
- Standard system directories

They don't know about your custom project location.

## The Solution

**Before** running `(ql:quickload :mud)`, you must register your project directory with ASDF:

```lisp
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :mud)
(mud:start)
```

## How to Do It - Step by Step

### Option 1: Recommended - Use getcwd (automatic)

```bash
# 1. Make sure you're in the project directory
cd /path/to/musical-guacamole

# 2. Start SBCL
sbcl

# 3. In SBCL, run these three lines IN ORDER:
> (push (uiop:getcwd) asdf:*central-registry*)
> (ql:quickload :mud)
> (mud:start)
```

The `(uiop:getcwd)` automatically gets your current working directory.

### Option 2: Manual - Specify the full path

```lisp
(push #p"/home/sophia/musical-guacamole/" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start)
```

Replace `/home/sophia/musical-guacamole/` with your actual path.

### Option 3: From Anywhere - Full absolute path

If you're not in the project directory:

```bash
sbcl
> (push #p"/full/path/to/musical-guacamole/" asdf:*central-registry*)
> (ql:quickload :mud)
> (mud:start)
```

## What This Does

`(push (uiop:getcwd) asdf:*central-registry*)` means:
- Get the current working directory
- Add it to the list of places ASDF searches for systems
- This allows Quicklisp to find your `mud.asd` file

## Full Session Example

```bash
$ cd /home/sophia/musical-guacamole
$ sbcl
This is SBCL 2.5.10, an implementation of ANSI Common Lisp.
...

* (push (uiop:getcwd) asdf:*central-registry*)
(#P"/home/sophia/musical-guacamole/")

* (ql:quickload :mud)
To load "mud":
  Load 1 ASDF system definition from directory /home/sophia/musical-guacamole/
  ; Loading "mud"
  ....
MUD
; Compilation finished in 0.001 seconds

* (mud:start)
[INFO] Initializing world...
[INFO] World initialized with 2 rooms
[INFO] MUD Server started on 127.0.0.1:8888

*
```

## If Still Not Working

### Check 1: Verify mud.asd exists
```bash
ls -la mud.asd
```

Should show the file exists.

### Check 2: Verify current directory
```lisp
> (uiop:getcwd)
#P"/home/sophia/musical-guacamole/"
```

Should show your project directory.

### Check 3: Check ASDF registry
```lisp
> asdf:*central-registry*
(#P"/home/sophia/musical-guacamole/" ...)
```

Your project should be in this list.

### Check 4: Try manual refresh
```lisp
> (asdf:clear-system-definitions)
> (push (uiop:getcwd) asdf:*central-registry*)
> (ql:quickload :mud)
```

## Complete Startup Procedure

Copy and paste this entire block into SBCL:

```lisp
;; Step 1: Tell ASDF where to find the project
(push (uiop:getcwd) asdf:*central-registry*)

;; Step 2: Load dependencies
(ql:quickload (list "usocket" "bordeaux-threads"))

;; Step 3: Load the MUD system
(ql:quickload :mud)

;; Step 4: Start the server
(mud:start)
```

## Quick Reference

| Problem | Solution |
|---------|----------|
| "System not found" | Add `(push (uiop:getcwd) asdf:*central-registry*)` |
| Still not found | Make sure you're in project directory: `(uiop:getcwd)` |
| Different location | Use `(push #p"/your/path/" asdf:*central-registry*)` |
| Can't start | Check mud.asd exists with `(probe-file "mud.asd")` |

## Why This Is Necessary

- Quicklisp only looks in specific directories
- Your project is in a custom location
- You must tell ASDF where to find it
- This is a one-time setup per SBCL session

## For Future Sessions

You can add this to your SBCL init file (~/.sbclrc) to make it automatic:

```lisp
;; At the top of ~/.sbclrc
(let ((mud-path #P"/home/sophia/musical-guacamole/"))
  (when (probe-file mud-path)
    (push mud-path asdf:*central-registry*)))
```

Then you can just run:
```lisp
(ql:quickload :mud)
(mud:start)
```

## Summary

✅ **The Fix**: `(push (uiop:getcwd) asdf:*central-registry*)`

Run this BEFORE `(ql:quickload :mud)` and it will work!

---

**Updated Documentation**: QUICKSTART.md, 00_START_HERE.md, and QUICK_REFERENCE.md have been updated with this critical step.
