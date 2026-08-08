---
name: reve-image
description: How to use the Reve Python SDK for image generation, remixing, and editing
---

# Reve Python SDK

The `reve` package is a Python client for the Reve image generation API.
Install it with `uv pip install reve`. It requires Python 3.10+.

## Authentication

Set the `REVE_API_TOKEN` environment variable, or pass `api_token=` when
constructing a `ReveClient`. Tokens look like `papi.xxx`.

```bash
export REVE_API_TOKEN="papi.your-token-here"
```

To check your Reve API tokens, go to `https://api.reve.com/console/keys`.
If you have none, or if you are not allowed to go to the API page, go to
`https://app.reve.com/account` and scroll to the bottom. Click "Enable API."
Once you accept the terms of service, add some API credits to your budget and
copy out the API token created for you. If you are not permitted to view API
keys on the api.reve.com/console/keys page, chances are that you are in the
wrong organization, and need to select another organization from the
user-section menu in the nav-footer bottom-left.

Optional env vars: `REVE_API_HOST` (default `https://api.reve.com`),
`REVE_PROXY_AUTHORIZATION`.

## Core Functions

The five functions in `reve.v2.image` are `create`, `extract_layout`,
`create_layout`, `render_layout`, and `reconcile_layout`. Structured types live in
`reve.v2.types`.

### Create an image from a prompt

```python
from reve.v2.image import create

result = create(prompt="A red dragon flying over mountains")
result.save("dragon.jpg")
```

Options: `references` (list of image inputs), `aspect_ratio` (`"16:9"`,
`"3:2"`, `"1:1"`, `"9:16"`, `"auto"`, and others — see the README for the full
list), `version`, `postprocessing`.

### Generate or edit with reference images

Pass reference images (each a plain image input — a file path, bytes, PIL
Image, or `ImageInput`):

```python
from reve.v2.image import create
from reve.v2.types import ImageInput

result = create(
    prompt="The subject in a magical forest",
    references=[ImageInput(data="photo.jpg")],
    aspect_ratio="1:1",
)
```

`ImageInput.data` accepts file paths (str), raw bytes, or PIL Images.
`ImageInput.ref` accepts a project reference string (`"id:<uuid>"` or
`"reference:@<name>"`).

To edit an image, put it first in the ordered references list. All references
are frames `0..N-1`; there is no separate base-image field:

```python
from reve.v2.image import create

result = create(
    prompt="Make the sky more dramatic with storm clouds",
    references=["original.jpg"],
)
result.save("edited.jpg")
```

### Work with layouts directly

`extract_layout` and `create_layout` return a `V2LayoutResponse` (a `.layout`,
no image), letting you separate "what to draw and where" from rendering:

```python
from reve.v2.image import create_layout, extract_layout, render_layout

# text -> layout -> image
created = create_layout(prompt="A cozy reading nook with an armchair and a bookshelf")
image = render_layout(layout=created.layout)
image.save("nook.jpg")

# image -> layout, optionally with an editing prompt
analyzed = extract_layout(image="nook.jpg", prompt="Remove the bookshelf")
```

- `create(prompt, *, references?, aspect_ratio?, postprocessing?, version?)` — prompt and ordered images to an image.
- `extract_layout(image, *, prompt?, version?)` — one image to a layout, optionally edited by a prompt.
- `create_layout(prompt?, *, references?, commands?, aspect_ratio?, version?)` — prompt and/or mixed references to a layout.
- `render_layout(layout, *, references?, postprocessing?, version?)` — target layout and optional mixed references to an image.
- `reconcile_layout(original_layout, edited_layout, *, version?)` — reconcile direct edits against their original layout.

`create_layout` requires at least a prompt or one reference. Each ordered
`Reference` may contain an `image`, a `layout`, an optional descriptive
`prompt`, or a supported combination. Commands require at least one reference.
Each command's `op` is `add`, `shift`, `remove`, `place`, `keep`, or `change`:

```python
from reve.v2.image import create_layout
from reve.v2.types import Bbox, LayoutCommand, Point, Reference

edited = create_layout(
    prompt="A desk scene",
    references=[Reference(layout=created.layout)],
    commands=[
        LayoutCommand(op="add", description="a lamp", at=Bbox(0.1, 0.1, 0.3, 0.4)),
        LayoutCommand(op="shift", label="mug", at=Point(0.5, 0.5), to=Point(0.7, 0.6)),
        LayoutCommand(op="change", label="book", new_description="an open notebook"),
    ],
)
```

For `render_layout`, image-bearing references provide pixel context and their
optional layouts identify source regions. Layout-only references provide
structural context and cannot be targeted as pixel sources.

Use `reconcile_layout` after a client directly edits a layout, especially when
a user or agent changes its prompt or regions. This keeps all parts of the
scene semantically consistent and prevents `render_layout` from seeing
inconsistent or contradictory scene descriptions:

```python
from reve.v2.image import reconcile_layout

reconciled = reconcile_layout(original_layout, edited_layout)
```

A `Layout`'s optional `width`/`height` are the pixel dimensions of its
coordinate frame. The layout endpoints emit them as multiples of 32; when
supplying them on input, provide both, each a multiple of 32, with
`width * height` between `3072*2560` and `4096*4096`.

`version` is optional on every v2 call: `"latest"` (the default) aliases the
flow's current pinned version, and the version actually used is reported back as
`response.version`.

## Postprocessing

Build pipelines with helpers from `reve.v1.postprocessing`:

```python
from reve.v2.image import create
from reve.v1.postprocessing import upscale, remove_background, fit_image, effect

result = create(
    prompt="A cat astronaut",
    postprocessing=[upscale(factor=2), remove_background()],
)
```

- `upscale(factor=2)` — enlarge the image
- `remove_background()` — transparent PNG output
- `fit_image(max_width=, max_height=, max_dim=)` — constrain dimensions (px, 1–4096)
- `effect(name, parameters=None)` — apply a named effect

## Response Object

`create()` and `render_layout()` return a `V2ImageResponse` with:

- `image` — `PIL.Image.Image | None`
- `image_bytes` — `bytes` (raw image data, always present)
- `layout` — `Layout | None` (layout the model generated)
- `request_id` — `str | None`
- `credits_used` — `int | None`
- `credits_remaining` — `int | None`
- `version` — `str | None`
- `content_violation` — `bool`
- `save(path, **kwargs)` — saves via PIL if available, otherwise writes raw bytes

`extract_layout()` and `create_layout()` return a
`V2LayoutResponse` with the same fields minus `image`/`image_bytes` (and no
`save`).

## Error Handling

All exceptions inherit from `ReveAPIError` (in `reve.exceptions`):

- `ReveAuthenticationError` — HTTP 401
- `ReveBudgetExhaustedError` — HTTP 402
- `ReveRateLimitError` — HTTP 429 (has `.retry_after`)
- `ReveValidationError` — HTTP 400
- `ReveContentViolationError` — content policy violation

```python
from reve.exceptions import ReveAPIError, ReveRateLimitError
from reve.v2.image import create

try:
    result = create(prompt="A sunset")
except ReveRateLimitError as exc:
    print(f"Rate limited — retry after {exc.retry_after}s")
except ReveAPIError as exc:
    print(f"API error (status {exc.status_code}): {exc.message}")
```

## Advanced: Custom Client

Pass a pre-configured `ReveClient` to any function:

```python
from reve import ReveClient
from reve.v2.image import create

client = ReveClient(
    api_token="papi.xxx",
    api_url="https://custom-endpoint.example.com",
)
result = create(prompt="A sunset", client=client)
```

## SDK Source Location

The SDK source lives at `sdk/python/` in the reve-core monorepo.
Example scripts are in `sdk/python/examples/`.
