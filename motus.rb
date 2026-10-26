#!/usr/bin/env ruby
# frozen_string_literal: true

# Motus kawaii — Ruby + Charm Ruby (bubbletea / lipgloss)
# Carrés rouges = bien placés · ronds bleus = présents mais mal placés.

require "bundler/setup"
require "bubbletea"
require "lipgloss"

# ─── Couleurs adaptatives ────────────────────────────────────────────────────

ACCENT = Lipgloss::AdaptiveColor.new(light: "#D6488C", dark: "#FF9EC4")
KO     = Lipgloss::AdaptiveColor.new(light: "#B3243C", dark: "#FF7B8A")
BLUE   = Lipgloss::AdaptiveColor.new(light: "#2456A8", dark: "#7EB1FF")
MUTED  = Lipgloss::AdaptiveColor.new(light: "#8A7D8F", dark: "#9A8CA0")
SOFT   = Lipgloss::AdaptiveColor.new(light: "#6E5A75", dark: "#C9BBD1")
WHITE  = Lipgloss::AdaptiveColor.new(light: "#FFFFFF", dark: "#FFF6F0")

# case carrée : lettre bien placée (fond rouge/rose)
SQUARE = Lipgloss::Style.new.bold(true).foreground(WHITE).background(KO).
         width(3).align(:center)
# case ronde : lettre présente mais mal placée (fond bleu)
ROUND = Lipgloss::Style.new.bold(true).foreground(WHITE).background(BLUE).
        width(3).align(:center)
# case inoccupée : contour
EMPTY = Lipgloss::Style.new.foreground(MUTED).width(3).align(:center)
# lettre donnée au départ (grisée, carré neutre)
GIVEN = Lipgloss::Style.new.bold(true).foreground(SOFT).width(3).align(:center)

TITLE_STYLE = Lipgloss::Style.new.bold(true).foreground(ACCENT)
MSG_STYLE   = Lipgloss::Style.new.bold(true).foreground(ACCENT)
GOOD_STYLE  = Lipgloss::Style.new.bold(true).foreground(
  Lipgloss::AdaptiveColor.new(light: "#1F7A4D", dark: "#7BD8A8")
)
BAD_STYLE   = Lipgloss::Style.new.bold(true).foreground(KO)
HELP_STYLE  = Lipgloss::Style.new.faint(true)
PAW_STYLE   = Lipgloss::Style.new.foreground(ACCENT)
PLAIN_S     = Lipgloss::Style.new

# ─── Niveaux ─────────────────────────────────────────────────────────────────

LEVELS = [5, 6, 7, 8, 9].freeze
MAX_TRIES = 6

# ─── Dictionnaire ────────────────────────────────────────────────────────────

DICT_PATH = File.join(__dir__, "data", "mots.txt")
DICT = begin
  all = Hash.new { |h, k| h[k] = [] }
  File.readlines(DICT_PATH, chomp: true).each { |w| all[w.length] << w }
  all
end.freeze

# ─── Messages ────────────────────────────────────────────────────────────────

class RevealMessage < Bubbletea::Message; end

# ─── Modèle ──────────────────────────────────────────────────────────────────

class Game
  include Bubbletea::Model

  attr_reader :menu, :level_idx, :grid, :secret

  def initialize
    @menu = true
    @level_idx = 0
    @width = 80
    @height = 24
    @paws = 0
  end

  def init
    [self, nil]
  end

  def start(level_idx)
    @menu = false
    @level_idx = level_idx
    @len = LEVELS[level_idx]
    pool = DICT[@len]
    @secret = pool.sample
    # sécurité : si le pool est vide (ne devrait pas arriver), replonger
    @secret = pool.first if @secret.nil?
    @first = @secret[0]
    @tries = []          # tableaux de feedback : :good / :present / :miss
    @current = +"#{@first}" + "·" * (@len - 1)
    @cursor = 1
    @revealed_index = 0  # lettres révélées au fil des échecs (après l'initiale)
    @over = false
    @won = false
    @message = "Trouve le mot (๑˃ᴗ˂)ﻭ"
    @reveal_queue = []   # [(ligne, colonne, case)] révélation animée
  end

  # ── update ──

  def update(message)
    case message
    when Bubbletea::WindowSizeMessage
      @width = message.width
      @height = message.height
      [self, nil]
    when RevealMessage
      tick_reveal
    when Bubbletea::KeyMessage
      handle_key(message)
    else
      [self, nil]
    end
  end

  def tick_reveal
    # dévoiler les cases une par une (200 ms chacune)
    unless @reveal_queue.empty?
      @reveal_queue.shift
      return [self, next_reveal]
    end
    [self, nil]
  end

  def next_reveal
    Bubbletea.tick(0.18) { RevealMessage.new }
  end

  def handle_key(message)
    key = message.to_s
    if @menu
      case key
      when "1", "2", "3", "4", "5"
        start(key.to_i - 1)
      when "down", "j", "right", "l"
        @level_idx = (@level_idx + 1) % LEVELS.size
      when "up", "k", "left", "h"
        @level_idx = (@level_idx - 1) % LEVELS.size
      when "enter", "space", " "
        start(@level_idx)
      when "q", "ctrl+c", "esc"
        return [self, Bubbletea.quit]
      end
      return [self, nil]
    end

    return [self, nil] if @over

    case key
    when "q", "ctrl+c"
      return [self, Bubbletea.quit]
    when "esc"
      @menu = true
    when "n", "m"
      # pendant la saisie, n et m sont des LETTRES du mot ; hors partie (over),
      # ils gardent leur rôle de raccourcis
      if @over
        key == "n" ? start(@level_idx) : @menu = true
      else
        type_letter(key)
      end
    when "left"
      @cursor = [@cursor - 1, 1].max
    when "right"
      @cursor = [@cursor + 1, @len - 1].min
    when "backspace"
      if @cursor > 1
        @cursor -= 1
        @current[@cursor] = "·"
      end
    when "enter", "space", " "
      submit if @cursor == @len
    else
      type_letter(key) if key =~ /^[a-z]$/
    end
    [self, nil]
  end

  def type_letter(key)
    return if @over
    if @cursor < @len
      @current[@cursor] = key
      @cursor += 1
      @message = @cursor == @len ? "Entrée pour valider ♪" : "Trouve le mot (๑˃ᴗ˂)ﻭ"
    end
  end

  def valid_word?(word)
    DICT[@len].include?(word)
  end

  def submit
    word = @current.is_a?(String) ? @current : @current.join
    unless valid_word?(word)
      @message = "#{word} n'est pas dans mon dictionnaire... (＞﹏＜)"
      return
    end

    feedback = score(word)
    @tries << [word, feedback]

    if word == @secret
      @over = true
      @won = true
      @message = "GAGNÉ ! #{MAX_TRIES - @tries.size + 1} essai(s) d'avance ☆*:.｡.o(≧▽≦)o.｡.:*☆"
      return
    end

    if @tries.size >= MAX_TRIES
      @over = true
      @won = false
      @message = "Perdu ! Le mot était #{@secret.upcase} (´；ω；`)"
      return
    end

    # révéler une lettre supplémentaire (comme à la TV) : la 1ʳᵉ lettre
    # inconnue du mot, pas nécessairement la suivante de la dernière ligne
    if @revealed_index < @len - 1
      @revealed_index += 1
    end
    reveal = @secret[0..@revealed_index]
    @current = +"#{reveal}" + "·" * (@len - 1 - @revealed_index)
    @cursor = @revealed_index + 1
    # cases à révéler en animation : la ligne qu'on vient de jouer
    @reveal_queue = (0...@len).map { |c| [@tries.size - 1, c] }
    @message = "Raté ! Une lettre en plus... ♪"
    next_reveal
  end

  # feedback Motus : carré (bien placé) / rond (présent mal placé) / rien
  def score(word)
    fb = Array.new(@len, :miss)
    secret_left = @secret.chars
    # pass 1 : bien placés
    word.chars.each_with_index do |c, i|
      if secret_left[i] == c
        fb[i] = :good
        secret_left[i] = nil
      end
    end
    # pass 2 : présents mal placés
    word.chars.each_with_index do |c, i|
      next if fb[i] == :good
      idx = secret_left.index(c)
      if idx
        fb[i] = :present
        secret_left[idx] = nil
      end
    end
    fb
  end

  # ── vue ──

  def view
    if @menu
      center(menu_view)
    else
      center(game_view)
    end
  end

  def center(content)
    lines = content.chomp.split("\n")
    visible = ->(l) { l.gsub(/\e\[[0-9;]*m/, "").length }
    max_w = lines.map { |l| visible.call(l) }.max || 0
    inner = [(@width - max_w) / 2, 0].max
    pad = " " * inner
    lines = lines.map { |l| pad + l }
    vpad = [(@height - lines.size) / 2, 0].max
    ([""] * vpad + lines).join("\n") + "\n"
  end

  def menu_view
    b = +""
    b << "\n"
    b << TITLE_STYLE.render(" ♡  M O T U S  ♡ ")
    b << "\n\n"
    b << PLAIN_S.render("Choisis ta longueur :")
    b << "\n\n"
    LEVELS.each_with_index do |len, i|
      prefix = format("  [%d] ", i + 1)
      line = format("%d lettres · %d essais", len, MAX_TRIES)
      b << (i == @level_idx ? MSG_STYLE : PLAIN_S).render(prefix + line) << "\n"
    end
    b << "\n"
    b << HELP_STYLE.render("↑↓ choisir · entrée jouer · 1-5 direct · q quitter")
    b << "\n"
    b
  end

  def cell(word, fb, col, revealed_upto: 99)
    c = word[col]
    return EMPTY.render(" ") unless c && c != "·"
    case fb[col]
    when :good then SQUARE.render(c)
    when :present then ROUND.render(c)
    # absente du mot : visible, en teinte douce, sans fond
    else GIVEN.render(c)
    end
  end

  def game_view
    b = +""
    b << TITLE_STYLE.render(" ♡  M O T U S  ♡ ")
    b << "\n"
    b << PLAIN_S.render("mot de #{@len} lettres · essai #{@tries.size + 1}/#{MAX_TRIES}")
    b << "\n\n"

    # lignes jouées
    @tries.each_with_index do |(word, fb), row|
      revealed_row = row # la ligne la plus récente se révèle progressivement
      line = (0...@len).map { |c| cell(word, fb, c) }.join
      b << line << "\n"
    end

    # ligne courante (si partie en cours)
    unless @over
      if @reveal_queue.empty? || @tries.empty?
        line = (0...@len).map do |c|
          ch = @current[c]
          if c == 0
            GIVEN.render(@first)
          elsif ch && ch != "·"
            # en cours de frappe : encadré neutre
            Lipgloss::Style.new.bold(true).foreground(SOFT).width(3).align(:center).render(ch)
          else
            EMPTY.render(@cursor == c ? "_" : " ")
          end
        end.join
        b << line << "\n"
      end
    end

    b << "\n"
    if @over
      b << (@won ? GOOD_STYLE : BAD_STYLE).render(@message) << "\n"
      b << PAW_STYLE.render("🐾 ♡ " * (1 + [@paws, 6].min)) << "\n" if @won
      b << HELP_STYLE.render("[n] rejouer · [m] menu · [q] quitter")
    else
      b << MSG_STYLE.render(@message) << "\n"
      b << HELP_STYLE.render("lettres · ←→ bouger · backspace · entrée valider · m menu · q quitter")
    end
    b << "\n"
    b
  end
end

if $PROGRAM_NAME == __FILE__
  Bubbletea.run(Game.new, alt_screen: true)
end
