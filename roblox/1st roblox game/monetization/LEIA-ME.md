# Criar os produtos e passes do jogo automaticamente

O jogo vende **30 developer products** (packs de Speed, dinheiro, trails, upgrades...) e **6 gamepasses** (2x Money, VIP...). Em vez de criar os 36 à mão no Creator Dashboard, um script cria todos de uma vez, já com nome, descrição, preço e ícone, e anota o número (id) de cada um em **`monetization/ids.json`**. O jogo lê os ids desse arquivo.

- `monetization/catalog.json`: a lista do que vai ser criado (nome, descrição, preço em Robux, ícone).
- `monetization/ids.json`: os ids. `0` = ainda não criado (a loja mostra "coming soon").
- Pode rodar o script quantas vezes quiser: ele **nunca cria duplicado**. O que já tem id, ou que já existe no jogo com o mesmo nome, é pulado.

---

## 1. Criar a chave de API (só uma vez)

1. Abra o **Creator Dashboard** → **Open Cloud** → **API Keys** (https://create.roblox.com/dashboard/credentials).
2. Clique em **Create API Key** e dê um nome, por exemplo `Steal a Seed loja`.
3. Em **Access Permissions**:
   - adicione **Developer Products**, escolha **esta experiência** (Steal a Seed) e marque **Read** e **Write**;
   - adicione **Game Passes**, escolha **esta experiência** e marque **Read** e **Write**.

   (O *Read* é para o script ver o que já existe e não criar de novo.)
4. Em **Accepted IP Addresses**, coloque `0.0.0.0/0` (ou só o seu IP).
5. Se quiser, coloque uma data de expiração (ex.: amanhã).
6. Clique em **Save & Generate Key** e **copie a chave**. Ela só aparece uma vez.

> ⚠️ A chave é como uma senha. **Não cole ela no chat, no Discord, nem em nenhum arquivo do projeto.** Ela só vai na sua janela do PowerShell (passo 3). O script nunca mostra a chave na tela.

## 2. Descobrir o Universe ID

No Creator Dashboard, abra a experiência. O número no endereço é o universe id:

```
create.roblox.com/dashboard/creations/experiences/<UNIVERSE_ID>/overview
```

Exemplo: `.../experiences/1234567890/overview` → `1234567890`.

## 3. Rodar o script (no SEU PowerShell)

Abra uma janela do **PowerShell** no seu computador (não no chat) e rode, trocando a pasta, a chave e o número:

```powershell
cd "C:\caminho\do\repo\roblox\1st roblox game"
$env:ROBLOX_API_KEY="cole-a-chave-aqui"

# Teste primeiro: mostra o que seria criado, sem mandar nada para o Roblox
node tools/create_monetization.mjs --dry-run

# Agora de verdade
node tools/create_monetization.mjs --universe 1234567890
```

No fim aparece uma tabela com cada item: o id, e se foi **created** (criado agora), **existing** (já existia) ou **failed** (deu erro, com a mensagem). Se algo falhar, é só rodar o mesmo comando de novo: ele cria só o que falta. Se o Roblox pedir para ir mais devagar (limite de requisições), o script espera e tenta de novo sozinho.

A variável `$env:ROBLOX_API_KEY` vale só para essa janela. Fechou a janela, ela some.

## 4. Avisar o Pixel

Quando terminar, avise o Pixel que **está pronto**. Ele faz o commit do `monetization/ids.json` e gera o place de novo, e aí a loja do jogo passa a vender tudo.

## 5. Apagar a chave

Depois de rodar, volte em **Open Cloud → API Keys** e **apague** a chave (ou desative/gere outra). Assim ninguém consegue usar ela depois.

---

### Dúvidas comuns

- **Quero mudar um preço.** Mude direto no Creator Dashboard (Monetization). O jogo lê o preço real de lá; o do `catalog.json` é só o preço inicial.
- **Os ícones aparecem cinza.** O Roblox ainda está revisando as imagens. Espere alguns minutos.
- **Apareceu "is not a ... of this universe".** O `ids.json` tem um id de outra experiência. Confira o `--universe`. Se for isso mesmo que você quer, troque aquele id por `0` e rode de novo.
