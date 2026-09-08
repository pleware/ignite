"""ignite — workspace toolchain bootstrapper (Python engine).

The engine is bootstrapped through the isolated pinned ``uv`` (layer 1) and
is the single source of logic for the verbs ``ensure``, ``bootstrap``,
``workspace-tree``, ``env``, and the ``pins/tools.sh`` ``TOOL_*`` plant.

Policy stays in data (``ignite.toml``, ``mise.toml``, ``workspace-layout.yaml``,
``pins/*.sh``). The engine only reads that data and executes.
"""

__version__ = "0.1.0"
