# Validación

Los resultados del README fueron transcritos de una ejecución compartida por el usuario en POCO F8 Ultra, Adreno 840, Android 16. No se adjuntan logs crudos del teléfono ni una réplica independiente. No hay validación para otras Adreno.

Evidencia comunicada: capas 33/33, descriptor KGSL, bibliotecas vendor correspondientes, generación completada y muestras GPU busy. OpenCL cargó por `sphal`. Modelo registrado `qwen35-4b-uncensored:latest`, identificador mostrado `531cd864240a` (no es un hash completo del GGUF). Memoria reportada por cada API no es VRAM dedicada: es un dispositivo de memoria unificada.

Limitaciones: una pasada, sin baseline CPU, sin controlar temperatura/frecuencia, prompt corto, sin prueba de llenado del contexto ni evaluación de exactitud. La salida original tenía un encabezado fijo incorrecto de 2B; se corrigió en esta versión.

La suite de repositorio comprueba sintaxis Bash, compilabilidad sintáctica de Python embebido e invariantes. No ejecuta GPU, no compila Android completo y no sustituye pruebas en el teléfono. Las revisiones de empaquetado posteriores a la ejecución comunicada requieren una nueva prueba end-to-end.

Para comparar: mismo GGUF y contexto, mismo prompt suficientemente largo, calentamiento por backend, varias repeticiones, registrar temperatura y orden de pruebas, informar mediana y dispersión. Separar TTFT, prefill y decode. Comparar respuestas con referencias antes de concluir equivalencia.
