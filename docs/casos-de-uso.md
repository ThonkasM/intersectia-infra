# Casos de uso y buenas prácticas

IntersectIA es, ante todo, una plataforma educativa. Estos son los casos de uso relevantes y las prácticas que los respaldan (investigación de gestión autónoma de intersecciones, AIM/V2X).

## Casos de uso principales

1. **Demostración educativa de gestión de intersecciones**
   Comparar, en vivo, una regla local (prioridad a la derecha, Art. 52 Bolivia), un gestor determinista FIFO y un gestor con IA, midiendo espera promedio y violaciones. Es el caso de uso central del taller.

2. **Intersecciones sin semáforo (signal-free / AIM)**
   El paradigma de *Autonomous Intersection Management* (Dresner & Stone) reemplaza el semáforo por un árbitro central que concede "reservas" de espacio-tiempo. IntersectIA implementa una versión simplificada basada en cola y decisión. Beneficios documentados en la literatura: menor demora media, menor consumo e idle time, mayor throughput frente a control por fases.

3. **Coordinación V2I/V2V (vehicle-to-infrastructure / vehicle)**
   El vehículo comparte posición y velocidad con la infraestructura; el gestor decide el orden de cruce. IntersectIA refleja esto con `playerState` (V2I) y el estado compartido de los autónomos.

4. **Investigación con aprendizaje por refuerzo**
   El entorno y la política entrenable permiten experimentar con MDPs de scheduling: la política aprende a no conceder el paso a un eje en conflicto con el que está ocupado, algo que una heurística greedy no captura.

5. **Gestión de tráfico mixto humano-autónomo**
   El vehículo del jugador (humano) convive con vehículos autónomos, incluyendo handover y detección de violaciones. Relevante porque la adopción de CAVs es gradual (penetración mixta).

6. **Simulación y gemelo digital ligero**
   El backend es determinista y sin estado compartido entre sesiones, lo que permite generar datasets de métricas (esperas, cruces, violaciones) para análisis.

## Buenas prácticas aplicadas

- **Un solo dueño de la verdad**: el backend simula; el frontend solo interpola. Evita divergencias de estado.
- **Fallback determinista**: la IA tiene timeout de 150 ms y cae al motor FIFO; la disponibilidad no depende del modelo.
- **Aislamiento por sesión**: cada visitante tiene una simulación independiente (salas de socket.io), lo que también aísla recursos y errores.
- **Trazabilidad del modelo**: el entrenamiento es reproducible (semilla fija), se evalúa contra heurística y aleatorio, y el artefacto se guarda en formato seguro (JSON, sin `pickle`).
- **Seguridad de servicios internos**: la IA solo acepta llamadas del backend (header `X-Internal-Token`); nunca se expone al navegador.
- **Escrituras no bloqueantes**: la persistencia en la base de datos no bloquea el tick de simulación.

## Métricas que vale la pena reportar

- Espera promedio por modo (`avgWaitSeconds`) y total de cruces.
- Violaciones de intersección (`totalViolations`).
- Throughput (cruces por minuto) y comparación entre modos.
- Costo de cómputo del módulo de decisión (debe mantenerse bajo 150 ms).

## Referencias

- Dresner, K. & Stone, P. (2008). *A Multiagent Approach to Autonomous Intersection Management*.
- Literatura reciente de MARL y control de señales para CAVs (co-optimización de trayectorias y fases).
- Marcos de V2X (C-V2X/SAE J2735) para comunicación vehículo-infraestructura.
