# Passadeira (treadmill)

Modelo low-poly feito no Blender (script `treadmill_lowpoly.py`). Escala: 1 unidade = 1 stud. Tem cerca de 7 studs de comprimento, 3 de largura e 4,5 de altura, e a consola fica à frente (+Y no Blender).

- `treadmill.fbx`: o ficheiro para importar no Roblox Studio (Import 3D).
- `treadmill.blend`: para editar no Blender.

## Como pôr no jogo
1. Roblox Studio → separador **Home** (ou **Avatar**) → **Import 3D** → escolher `treadmill.fbx` → **Import**.
2. Aparece um Model no Workspace. Mudar o nome para **`Treadmill`** (exatamente assim).
3. (Opcional) Pintar as peças com cores mais vivas: selecionar cada parte e mudar **Color** e **Material**.
4. Botão direito no Model → **Save to File** → guardar em `roblox/1st roblox game/assets/Treadmill.rbxm`.
5. Avisar o Pixel. Ele atualiza o mapa e todas as passadeiras dos lotes passam a ser esta.

O jogo ajusta o tamanho sozinho ao espaço da passadeira de cada lote. A parte que dá Speed (a passadeira invisível de baixo) continua igual. Se a consola ficar virada para o lado errado, põe um atributo `Yaw` (por exemplo 180) no Model antes do Save to File.
