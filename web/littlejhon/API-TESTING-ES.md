# Cómo probar la API — explicado fácil

Esta guía te muestra cómo un **cliente B2B (broker, fintech, fondo, custodio)** usaría
nuestra API ANTES de que su usuario firme una transacción con un token RWA. La idea es:

```
El backend del broker      Nuestra API              El contrato ShieldRWAGuard
──────────────────────     ─────────────             ──────────────────────────
  un usuario quiere                                             │
  mover un token RWA                                            │
        │                                                       │
        │  POST /api/risk-check   (gratis, instantáneo)         │
        ├──────────────────────────►│                           │
        │ ◄────────────────────────│ decisión: ALLOW            │
        │                                                       │
        │  POST /api/attest                                     │
        ├──────────────────────────►│                           │
        │ ◄────────────────────────│ {firma, nonce, ...}        │
        │                                                       │
        │ (el broker hace que su usuario firme con su wallet)   │
        │                                                       │
        │  guard.safeTransfer(... firmaUsuario, firmaBackend)   │
        │ ─────────────────────────────────────────────────────►│
        │                                                       │ ✅
```

El broker nos paga una suscripción (o fee por llamada). El contrato **NO acepta** una
`safeTransfer` sin nuestra firma de attestation — sin nosotros no se mueve nada.

---

## 1. Levanta la API en tu compu

```powershell
cd web\littlejhon
pnpm install
pnpm dev
# → API corriendo en http://localhost:3000/api
```

Para confirmar que está viva (no necesita body):

```powershell
curl http://localhost:3000/api/health
```

---

## 2. Los endpoints que vas a usar

| Endpoint | Método | Para qué sirve | ¿Necesita auth? |
|---|---|---|---|
| `/api/health` | GET | Verifica que la API está viva | No |
| `/api/risk-check` | POST | Evalúa el riesgo SIN firmar (solo lectura) | No (en prod: API key) |
| `/api/attest` | POST | Evalúa y FIRMA un `RiskAttestation` si pasa | No (en prod: API key) |
| `/api/assets` | GET | Lista de assets que conoce la política | No |
| `/api/policies/{policyId}` | GET | Describe las reglas de una política | No |

Para simular un broker: **primero `/api/risk-check`**, después **`/api/attest`** si el broker
decide proceder. Los dos endpoints reciben casi el mismo cuerpo.

---

## 3. Qué tienes que mandarle a la API

```jsonc
{
  "chainId": 46630,                              // 46630 (Robinhood) o 421614 (Arbitrum Sepolia)
  "from": "0xWalletDelUsuario...",               // dirección que va a firmar la tx
  "to": "0xDestinatario...",                     // el que recibe
  "asset": "AAPLx",                              // ticker como está registrado en el registry
  "token": "0xDireccionDelToken...",             // OPCIONAL: address explícito (override del registry)
  "amount": "25000000",                          // string de "unidades base" (25 AAPLx con 6 decimales)
  "value": "0",                                  // valor nativo (string) — casi siempre "0"
  "data": "0xa9059cbb000...",                    // OPCIONAL: calldata ABI (para detectar APPROVE/TRANSFER_FROM)
  "context": {
    "action": "TRANSFER",                        // TRANSFER | APPROVE | TRANSFER_FROM
    "policyId": "rwa-retail-v1",                 // OPCIONAL: qué política aplicar
    "scenarioId": "safe-transfer",               // OPCIONAL: etiqueta el escenario conocido
    "recipientEligible": true,                   // OPCIONAL: override de la verificación de elegibilidad
    "spender": "0xQuienGastara..."               // OPCIONAL: obligatorio para APPROVE
  }
}
```

`/api/attest` recibe lo mismo más `nonce` y `deadline` opcionales (los dos como strings decimales).

### Lo que te responde

```jsonc
{
  "decision": "ALLOW",                              // ALLOW | WARN | REQUIRE_APPROVAL | BLOCK
  "riskScore": 12,                                  // 0 a 100 (menor = más seguro)
  "reasons": [
    { "code": "LOW_RISK", "message": "Asset oficial, recipient elegible...", "severity": "info" }
  ],
  "humanSummary": "Operación permitida...",
  "operationHash": "0xab12...",                     // hash del request — mismo input = mismo hash
  "policyId": "rwa-retail-v1",
  "simulationId": "sim_abc123",                     // úsalo para correlacionar logs
  "prerequisites": [],                              // cosas que faltan para ejecución on-chain
  "decodedAction": "TRANSFER"
}
```

Si pegaste `/api/attest` y `decision === "ALLOW"`, además te llega esto:

```jsonc
{
  // ... mismos campos de arriba MÁS:
  "attestation": {
    "token": "0x1111...",
    "from": "0xWalletUsuario...",
    "to": "0xDestinatario...",
    "amount": "25000000",
    "nonce": "1234567890",
    "deadline": "1735689600",                       // unix segundos
    "riskScore": 12,
    "signer": "0x4e5A...AD6D",                      // quien firmó (debe ser el trustedSigner on-chain)
    "signature": "0xabcd...1c"                      // esto se pasa como attestationSig a safeTransfer
  }
}
```

---

## 4. Seis escenarios de broker que puedes probar AHORA MISMO

Estos usan los assets demo que vienen con la API. Cambia `from` por una wallet tuya.

### Escenario A — Transferencia segura (esperado: `ALLOW`)

Un usuario verificado del broker quiere mandar 25 AAPLx a un destinatario elegible.

**PowerShell:**
```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx"
  amount = "25000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "safe-transfer"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**curl (bash):**
```bash
curl -X POST http://localhost:3000/api/risk-check \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 46630,
    "from": "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D",
    "to": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "asset": "AAPLx",
    "amount": "25000000",
    "value": "0",
    "context": {
      "action": "TRANSFER",
      "policyId": "rwa-retail-v1",
      "scenarioId": "safe-transfer",
      "recipientEligible": true
    }
  }'
```

**Respuesta esperada:** `decision: "ALLOW"`, `riskScore: 12`, razones incluyen `LOW_RISK`.

---

### Escenario B — Aprobación ilimitada a un spender desconocido (esperado: `BLOCK`)

El usuario intenta darle poder de gastar ilimitado a una dirección que NO está en el allowlist.
Patrón clásico de phishing / drainer.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xdead00000000000000000000000000000000beef"
  asset = "AAPLx"
  amount = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
  value = "0"
  context = @{
    action = "APPROVE"
    policyId = "rwa-retail-v1"
    scenarioId = "unlimited-approval"
    spender = "0xdead00000000000000000000000000000000beef"
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Esperado:** `decision: "BLOCK"`, `riskScore: 94`, `reasons[0].code: "UNLIMITED_APPROVAL"`.

El broker NO debe pasarle esto al wallet del usuario para firmar.

---

### Escenario C — Token falsificado (esperado: `BLOCK`)

Mismo usuario, mismo destinatario, pero el asset es un token conocido como fake.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx-FAKE"
  amount = "10000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "fake-token"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Esperado:** `decision: "BLOCK"`, `riskScore: 96`, `reasons[0].code: "FAKE_TOKEN"`.

---

### Escenario D — Asset restringido a destinatario fuera de la lista (esperado: `REQUIRE_APPROVAL`)

El usuario quiere mandar NVDAx a alguien que NO está en la lista de elegibles de NVDAx.
La política no bloquea — escala el caso. El broker puede pedirle a su oficial de compliance
una aprobación manual.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xdddddddddddddddddddddddddddddddddddddddd"
  asset = "NVDAx"
  amount = "12000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "ineligible-recipient"
    recipientEligible = $false
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Esperado:** `decision: "REQUIRE_APPROVAL"`, `riskScore: 72`, razones mencionan asset restringido
y destinatario no elegible.

---

### Escenario E — La misma operación en Arbitrum Sepolia (esperado: `ALLOW`)

La API es multi-chain. Cambia `chainId` de `46630` a `421614` y apuntas al deploy de Arbitrum.
La dirección del contrato es la misma (`0xB4f9C...d096`) pero el dominio EIP-712 cambia.

```powershell
$body = @{
  chainId = 421614
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx"
  amount = "25000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "safe-transfer"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/risk-check" -Method Post `
  -Body $body -ContentType "application/json"
```

**Esperado:** misma respuesta `ALLOW`. Si después llamas `/api/attest` con `chainId: 421614`,
la firma que te devuelve se "amarra" al dominio de Arbitrum — la misma firma NO funcionaría
en Robinhood, y al revés tampoco.

---

### Escenario F — Conseguir la firma de attestation lista para mandar on-chain

Cuando el broker tiene luz verde del `/risk-check`, la siguiente llamada es `/api/attest`. Te
devuelve un `RiskAttestation` firmado por el backend que el broker (o el wallet del usuario)
pasa a `guard.safeTransfer(...)`.

**Pre-requisito:** `TRUSTED_SIGNER_PRIVATE_KEY` tiene que estar puesto en `web/littlejhon/.env`.
Hasta que no lo pongas, este endpoint te responde con `prerequisites: ["Set TRUSTED_SIGNER_PRIVATE_KEY to enable backend attestations."]`.

```powershell
$body = @{
  chainId = 46630
  from = "0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D"
  to = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  asset = "AAPLx"
  amount = "25000000"
  value = "0"
  context = @{
    action = "TRANSFER"
    policyId = "rwa-retail-v1"
    scenarioId = "safe-transfer"
    recipientEligible = $true
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/api/attest" -Method Post `
  -Body $body -ContentType "application/json"
```

**Esperado:** la respuesta normal de `ALLOW` más un objeto `attestation` con `nonce`,
`deadline`, `signer` y `signature`. El broker después le pide al wallet del usuario que
firme el typed data `ShieldTransfer` y manda ambas firmas a `safeTransfer(...)`.

---

## 5. Postman / Insomnia / Bruno

Importa esta colección (pegala como raw):

```json
{
  "info": { "name": "ShieldRWAGuard API", "_postman_id": "shield-rwa-guard" },
  "item": [
    {
      "name": "POST /risk-check — transferencia segura",
      "request": {
        "method": "POST",
        "header": [{ "key": "Content-Type", "value": "application/json" }],
        "url": "http://localhost:3000/api/risk-check",
        "body": {
          "mode": "raw",
          "raw": "{\n  \"chainId\": 46630,\n  \"from\": \"0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D\",\n  \"to\": \"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n  \"asset\": \"AAPLx\",\n  \"amount\": \"25000000\",\n  \"value\": \"0\",\n  \"context\": {\n    \"action\": \"TRANSFER\",\n    \"policyId\": \"rwa-retail-v1\",\n    \"scenarioId\": \"safe-transfer\",\n    \"recipientEligible\": true\n  }\n}"
        }
      }
    },
    {
      "name": "POST /attest — mismo intent",
      "request": {
        "method": "POST",
        "header": [{ "key": "Content-Type", "value": "application/json" }],
        "url": "http://localhost:3000/api/attest",
        "body": {
          "mode": "raw",
          "raw": "{\n  \"chainId\": 46630,\n  \"from\": \"0x4e5A7B9F7F66c208bDDeD352356B33a3A634AD6D\",\n  \"to\": \"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n  \"asset\": \"AAPLx\",\n  \"amount\": \"25000000\",\n  \"value\": \"0\",\n  \"context\": {\n    \"action\": \"TRANSFER\",\n    \"policyId\": \"rwa-retail-v1\",\n    \"scenarioId\": \"safe-transfer\",\n    \"recipientEligible\": true\n  }\n}"
        }
      }
    }
  ]
}
```

---

## 6. Qué hace falta para que sea "broker real" y no demo

La API funciona contra **assets mock** (el registry en [`server/assets/registry.ts`](server/assets/registry.ts)).
Para integrar un broker real hay que sumar:

| Hoy (demo) | Integración real lista para producción |
|---|---|
| Direcciones mock `0x1111...`, `0x2222...`, `0x3333...` | Contratos RWA reales whitelisteados en `ShieldRWAGuard` |
| `ASSET_REGISTRY_MODE=mock` | `ASSET_REGISTRY_MODE=env` con `NEXT_PUBLIC_DEMO_*_TOKEN` llenas |
| `recipientEligible` que se puede pisar desde el body | Elegibilidad sale de `ComplianceRegistry.isVerified(to)` on-chain |
| Sin API key | API key por broker + rate limit + billing por llamada |
| Wallet del deployer = trusted signer | Wallet dedicada para `trustedSigner`, rotada con `setTrustedSigner` |
| Risk score sólo con heurísticas internas | Enriquecido con feeds externos (Chainalysis, TRM, listas de sanciones) |
| Sin protección de replay | Dedup server-side por `(from, nonce)` para evitar firma doble |

Puedes simular "real" así:

1. Pon en `.env` un `NEXT_PUBLIC_DEMO_AAPL_TOKEN` con un ERC20 real que hayas deployado en testnet
2. Cambia `ASSET_REGISTRY_MODE=env`
3. Pon `TRUSTED_SIGNER_PRIVATE_KEY` en `.env`
4. Verifica los wallets de prueba on-chain con `ComplianceRegistry.verifyIdentity(...)`
5. Whitelistea el token con `ShieldRWAGuard.whitelistToken(...)`

Después de esto, un `ALLOW` de `/api/attest` te da una firma que el contrato deployado
SÍ acepta en `safeTransfer(...)`.

---

## 7. Tabla rápida de "qué debería responder cada escenario"

| Cuerpo del request | `decision` | `riskScore` | Primer reason code |
|---|---|---|---|
| `scenarioId: "safe-transfer"`, AAPLx | `ALLOW` | 12 | `LOW_RISK` |
| `scenarioId: "unlimited-approval"`, monto max | `BLOCK` | 94 | `UNLIMITED_APPROVAL` |
| `scenarioId: "fake-token"`, AAPLx-FAKE | `BLOCK` | 96 | `FAKE_TOKEN` |
| `scenarioId: "ineligible-recipient"`, NVDAx | `REQUIRE_APPROVAL` | 72 | `RESTRICTED_ASSET` |
| `asset: "DOGEx"` desconocido | `BLOCK` | 95 | `UNKNOWN_ASSET` |
| `chainId: 137` (polygon, no configurado) | `BLOCK` | 95 | `UNSUPPORTED_CHAIN` |

Si alguno responde algo distinto, el motor de políticas en [`server/policies/engine.ts`](server/policies/engine.ts)
se desvió — ábrelo y revisa.

---

## 8. Cómo monitorear lo que la API hace

El log de auditoría escribe a `stdout` (lo ves en la terminal donde corres `pnpm dev`):

```
[audit] risk_check { simulationId: 'sim_ab12cd34ef', decision: 'ALLOW', riskScore: 12, policyId: 'rwa-retail-v1' }
[audit] attest_signed { simulationId: 'sim_ab12cd34ef', signer: '0x4e5A...', riskScore: 12 }
```

En producción esto se mandaría a un SIEM / OpenTelemetry. El `simulationId` es tu llave de
unión entre `/risk-check` → `/attest` → tx on-chain.
