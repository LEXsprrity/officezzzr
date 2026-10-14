# Como subir os ícones para o Roblox

O jogo usa os 21 ícones desta pasta (`Shop.png`, `Robux.png`, ...). O Roblox só mostra imagens que foram **enviadas** para ele, e cada imagem enviada ganha um número (o *asset id*). Esses números ficam em **`icons/ids.json`**:

```json
{
  "Bag": 0,
  "Bat": 0,
  ...
}
```

- `0` quer dizer "ainda não enviado": o jogo continua mostrando o emoji de antes (🛒, 🎁, ...). Nada quebra.
- Quando um número é colocado, o ícone aparece no lugar do emoji (HUD, loja, placas do mapa).
- Você **não precisa mexer em código Lua**. Só neste arquivo.

Tem dois jeitos de preencher o `ids.json`: o automático (recomendado) e o manual.

---

## (a) Jeito automático: o uploader

Ele envia os 21 PNGs de uma vez e escreve os números no `ids.json` sozinho.

### 1. Criar uma chave de API (só uma vez)
1. Abra **https://create.roblox.com/dashboard/credentials** (logado na sua conta).
2. Clique em **Create API Key**.
3. Dê um nome, por exemplo `Steal a Seed icons`.
4. Em **Access Permissions**, escolha **Assets** e marque **Read** e **Write**.
5. Em **Accepted IP Addresses**, adicione `0.0.0.0/0` (ou o seu IP).
6. Se quiser, coloque uma data de expiração.
7. Clique em **Save & Generate Key** e **copie a chave**. Ela só aparece uma vez.

> ⚠️ A chave é como uma senha. **Nunca** cole ela em um arquivo do projeto, no Discord ou num commit. O uploader só lê a chave da variável de ambiente e nunca imprime ela na tela.

### 2. Descobrir o seu User ID
Abra o seu perfil no site do Roblox. O número na barra de endereço é o seu User ID, por exemplo `roblox.com/users/123456789/profile` → `123456789`.
(Se o jogo for de um **grupo**, use o ID do grupo, que aparece na página do grupo, com `ROBLOX_GROUP_ID` no lugar de `ROBLOX_USER_ID`.)

### 3. Rodar o uploader (PowerShell)
Abra o PowerShell **na pasta do jogo** (a que tem o `default.project.json`) e rode:

```powershell
$env:ROBLOX_API_KEY = "cole-a-chave-aqui"
$env:ROBLOX_USER_ID = "123456789"

# Primeiro, um teste que não envia nada (nem precisa da chave):
lune run tools/upload_icons.luau --dry-run

# Agora de verdade:
lune run tools/upload_icons.luau
```

As variáveis `$env:` valem só para essa janela do PowerShell. Fechou a janela, elas somem (é de propósito).

O uploader:
- envia cada PNG como **Image** e espera o Roblox terminar de processar;
- escreve o número de cada ícone no `icons/ids.json` (logo depois de cada um, então se der erro no meio, o que já foi fica salvo);
- pula os ícones que já têm número. Para enviar de novo: `--force`. Só alguns: `--only Shop,Robux`.

Ele também cria `icons/uploads.json` com os detalhes de cada envio (sem a chave).

### 4. Ver no jogo
Depois de rodar, faça o build de novo (`rojo build -o StealASeed.rbxlx`) ou, se estiver com `rojo serve` aberto, o Studio já pega o `ids.json` novo. Faça um commit do `icons/ids.json`.

> As imagens passam pela moderação do Roblox. Enquanto uma estiver em análise (ou se for recusada), aquele ícone aparece vazio. Normalmente leva poucos minutos.

### Deu erro?
- **"ROBLOX_API_KEY is not set"**: você não rodou a linha `$env:ROBLOX_API_KEY = ...` nessa janela.
- **HTTP 401 / 403**: a chave está errada, expirou, não tem **Assets Read + Write**, ou o IP não está liberado.
- **HTTP 429**: muitas requisições; o uploader espera e tenta de novo sozinho.
- **"uploaded as decal ..., but its image id couldn't be read"**: só acontece com `--type Decal`. Veja "Decal x Image" abaixo.

---

## (b) Jeito manual: pelo Studio

1. Abra o jogo no Roblox Studio.
2. **View → Asset Manager**.
3. Clique em **Bulk Import** e escolha **todos os PNGs desta pasta** `icons/`.
4. Espere terminar. Eles aparecem em **Images**.
5. Para cada imagem: clique com o botão direito → **Copy Asset ID**.
6. Cole o número no `icons/ids.json`, na linha com o **mesmo nome do arquivo**. Exemplo: o ID de `Shop.png` vai em `"Shop"`:
   ```json
   "Shop": 123456789012,
   ```
   (Só o número, sem aspas, sem `rbxassetid://`.)
7. Salve o arquivo, faça o build de novo e o commit.

---

## Decal x Image (por que o número certo importa)

O Roblox tem dois tipos de asset para imagem:
- **Image**: a imagem em si. O número dela é o que um `ImageLabel` usa. **É esse que vai no `ids.json`.**
- **Decal**: um "embrulho" em volta de uma imagem. O número do decal é **diferente** do número da imagem, e um `ImageLabel` com o número do decal fica **vazio** no jogo.

O uploader envia como **Image**, então o número já sai certo. O Asset Manager (jeito manual) também mostra os números de **Image**.

Se você tiver só o número de um **decal** (por exemplo, enviado pelo site em "Create → Decals", ou o uploader com `--type Decal` que não conseguiu achar a imagem): no Studio, crie um `ImageLabel` qualquer, cole o número do decal na propriedade **Image** e aperte Enter. O Studio troca sozinho para `rbxassetid://<número da imagem>`. Copie esse número para o `ids.json` e apague o `ImageLabel`.

---

Créditos: Icons by @gvesster (Free Icon Pack). A licença permite uso comercial (o crédito é opcional), mas não permite revender os ícones nem dizer que fomos nós que fizemos.
