СЛОИ ТЁМНОГО ЛЕСА ДЛЯ GODOT 4 (вид сбоку, игрок ходит влево и вправо)

Файлы
  01_sky.png    небо с луной, не двигается          motion_scale x = 0     320 x 180
  02_far.png    дальний лес                         motion_scale x = 0.12  670 x 180
  03_mid.png    средний лес                         motion_scale x = 0.30  1188 x 180
  04_back.png   деревья позади тропы                motion_scale x = 0.55  1908 x 180
  05_main.png   земля, мост, кусты, часовня, дерево motion_scale x = 1     3204 x 180
  06_front.png  передний план (стволы, трава, листва) motion_scale x = 1.35 4212 x 180
  ground_heights.json  высота пола ground_y[x] для каждого x от 0 до 3200
  hiding_spots.json    17 мест, где можно спрятаться (x, width), границы зон
  forest_parallax.tscn готовая сцена со всеми слоями

Как подключить
  1. Скопируй папку forest_layers в корень проекта (res://forest_layers).
  2. Project Settings:
     Display > Window > Viewport Width 320, Height 180,
     Window Width Override 1280, Height Override 720, Stretch Mode = viewport,
     Rendering > Textures > Default Texture Filter = Nearest.
  3. Добавь forest_parallax.tscn в уровень. Игрока (CharacterBody2D) помести
     между Background и Foreground: у фона слой -1, у переднего плана слой 1,
     игрок на слое 0.
  4. Camera2D: Limit Left 0, Limit Right 3200, Limit Top 0, Limit Bottom 180.
     Игрок движется только по X. Y пола берёшь из ground_heights.json
     (от 145 до 155, на мосту, у часовни и у алтаря ровно 150).
  5. Слой 06_front рисуется поверх игрока: когда игрок заходит за передний
     ствол, он пропадает за ним. Это нужно для эффекта "проходит мимо деревьев".

Чего нет в PNG: светлячки, туман, мерцание свечей и воды, пульсация рун,
падающие листья. Они анимируются в HTML-версии (rabbit-forest-sidescroll.html),
в Godot их надо делать через GPUParticles2D, AnimatedSprite2D или шейдер.

Свечение грибов, фонарей и окон нарисовано в PNG статично (без пульсации).
