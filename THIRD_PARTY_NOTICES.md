# Fuentes y terceros

Este repositorio contiene scripts de integración y parches generados; descarga proyectos externos al instalar. No incluye modelos ni bibliotecas Qualcomm.

- Ollama v0.40.16: https://github.com/ollama/ollama (MIT; consultar licencia de la versión).
- llama.cpp b12177 / GGML: https://github.com/ggml-org/llama.cpp (MIT; consultar licencia de la versión).
- Parches Vulkan consultados: https://github.com/ggml-org/llama.cpp/pull/30821 y /pull/30829.
- Referencia para carga Qualcomm OpenCL SPHAL: https://github.com/Ishabdullah/OpenCL-S24-Ultra ; revisar sus términos antes de redistribuir material derivado o binarios.
- Referencias Android/Vulkan: https://github.com/DioNanos/ollama-termux y https://github.com/josedav29/ollama-vulkan-adreno-support .
- Paquetes Termux: https://github.com/termux/termux-packages ; cada paquete tiene sus términos.

Los drivers instalados en /vendor pertenecen a sus respectivos titulares y no están cubiertos por MIT de este proyecto. Los modelos tienen licencias independientes: que un archivo sea local no concede permiso de redistribución.

Las etiquetas, parches descargados y paquetes no están bloqueados mediante hashes criptográficos en esta edición. No constituye un build hermético ni una garantía de cadena de suministro. Revisa las fuentes descargadas y conserva las licencias upstream al redistribuir artefactos compilados.
