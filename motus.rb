#!/usr/bin/env ruby
# frozen_string_literal: true

# Motus kawaii — Ruby + Charm Ruby (bubbletea / lipgloss)
# Grille complète visible (6 essais × N lettres), lettres colorées sans fond,
# lettres bien placées reportées sur la ligne suivante (comme à la TV),
# définition du mot à la fin (Wiktionary).

require "bundler/setup"
require "bubbletea"
require "lipgloss"
require "json"
require "open-uri"

# ─── Couleurs adaptatives ────────────────────────────────────────────────────

ACCENT = Lipgloss::AdaptiveColor.new(light: "#D6488C", dark: "#FF9EC4")
GOOD   = Lipgloss::AdaptiveColor.new(light: "#C41E3D", dark: "#FF7B8A")
PRES   = Lipgloss::AdaptiveColor.new(light: "#2456A8", dark: "#7EB1FF")
MISS   = Lipgloss::AdaptiveColor.new(light: "#B0A3B5", dark: "#6E5F73")
GIVEN_C = Lipgloss::AdaptiveColor.new(light: "#6E5A75", dark: "#C9BBD1")
MUTED  = Lipgloss::AdaptiveColor.new(light: "#8A7D8F", dark: "#9A8CA0")
MUTED_S = Lipgloss::Style.new.foreground(MUTED)
SOFT   = Lipgloss::AdaptiveColor.new(light: "#6E5A75", dark: "#C9BBD1")
KO     = Lipgloss::AdaptiveColor.new(light: "#B3243C", dark: "#FF7B8A")

TITLE_STYLE  = Lipgloss::Style.new.bold(true).foreground(ACCENT)
GOOD_STYLE   = Lipgloss::Style.new.bold(true).foreground(GOOD)
PRES_STYLE   = Lipgloss::Style.new.bold(true).foreground(PRES)
MISS_STYLE   = Lipgloss::Style.new.foreground(MISS)
GIVEN_STYLE  = Lipgloss::Style.new.bold(true).foreground(GIVEN_C)
TYPING_STYLE = Lipgloss::Style.new.bold(true).foreground(ACCENT)
CURSOR_STYLE = Lipgloss::Style.new.bold(true).foreground(ACCENT).underline(true)
MSG_STYLE    = Lipgloss::Style.new.bold(true).foreground(ACCENT)
WIN_STYLE    = Lipgloss::Style.new.bold(true).foreground(
  Lipgloss::AdaptiveColor.new(light: "#1F7A4D", dark: "#7BD8A8")
)
LOSE_STYLE   = Lipgloss::Style.new.bold(true).foreground(KO)
HELP_STYLE   = Lipgloss::Style.new.faint(true)
PAW_STYLE    = Lipgloss::Style.new.foreground(ACCENT)
DEF_TITLE    = Lipgloss::Style.new.bold(true).foreground(
  Lipgloss::AdaptiveColor.new(light: "#1F7A4D", dark: "#7BD8A8")
)
DEF_STYLE    = Lipgloss::Style.new.foreground(SOFT)
PLAIN_S      = Lipgloss::Style.new

# ─── Niveaux / dictionnaire ──────────────────────────────────────────────────

LEVELS = [5, 6, 7, 8, 9].freeze
MAX_TRIES = 6

DATA = File.join(__dir__, "data")
DICT = begin
  h = Hash.new { |h2, k| h2[k] = [] }
  File.readlines(File.join(DATA, "mots.txt"), chomp: true).each { |w| h[w.length] << w }
  h
end.freeze
SECRETS = begin
  h = Hash.new { |h2, k| h2[k] = [] }
  File.readlines(File.join(DATA, "secrets.txt"), chomp: true).each { |w| h[w.length] << w }
  h
end.freeze

# ─── Messages ────────────────────────────────────────────────────────────────

class DefMessage < Bubbletea::Message; end

class RefreshMessage < Bubbletea::Message; end

# ─── Modèle ──────────────────────────────────────────────────────────────────

class Game
  include Bubbletea::Model

  def initialize
    @menu = true
    @level_idx = 0
    @width = 80
    @height = 24
  end

  def init
    [self, refresh_tick]
  end

  def refresh_tick
    Bubbletea.tick(0.5) { RefreshMessage.new } # rafraîchit (définition asynchrone)
  end

  def start(level_idx)
    @menu = false
    @level_idx = level_idx
    @len = LEVELS[level_idx]
    @secret = SECRETS[@len].sample || DICT[@len].sample
    @tries = []
    @states = []           # feedback par ligne jouée
    @current = Array.new(@len) { |i| i.zero? ? @secret[0] : nil }
    @locked = Array.new(@len, false)
    @locked[0] = true
    @cursor = next_free(0, +1)
    @revealed = 0
    @over = false
    @won = false
    @definition = nil
    @message = "Trouve le mot (๑˃ᴗ˂)ﻭ"
  end

  # ── update ──

  def update(message)
    case message
    when Bubbletea::WindowSizeMessage
      @width = message.width
      @height = message.height
      [self, nil]
    when RefreshMessage
      [self, refresh_tick]
    when Bubbletea::KeyMessage
      handle_key(message)
    else
      [self, nil]
    end
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

    case key
    when "q", "ctrl+c"
      return [self, Bubbletea.quit]
    when "esc"
      @menu = true
    when "n"
      start(@level_idx) if @over
    when "left"
      @cursor = next_free(@cursor, -1)
    when "right"
      @cursor = next_free(@cursor, +1)
    when "backspace"
      clear_free_before(@cursor)
    when "enter", "space", " "
      submit
    else
      type_letter(key) if key =~ /^[a-z]$/
    end
    [self, nil]
  end

  # ── saisie : le curseur saute les cases correctes reportées ──

  def next_free(from, dir)
    c = from
    loop do
      c += dir
      break if c < 0 || c >= @len
      break unless @locked[c]
    end
    c.between?(0, @len - 1) ? c : from
  end

  def clear_free_before(cursor)
    c = cursor - 1
    while c >= 0
      unless @locked[c]
        @current[c] = nil
        @cursor = c
        return
      end
      c -= 1
    end
  end

  def type_letter(key)
    return if @over || @cursor >= @len || @locked[@cursor]
    @current[@cursor] = key
    @cursor = next_free(@cursor, +1)
    @message = "Entrée pour valider ♪"
  end

  def valid_word?(word)
    DICT[@len].include?(word)
  end

  def score(word)
    fb = Array.new(@len, :miss)
    secret_left = @secret.chars
    word.chars.each_with_index do |c, i|
      if secret_left[i] == c
        fb[i] = :good
        secret_left[i] = nil
      end
    end
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

  def fetch_definition(word)
    Thread.new do
      defs =
        begin
          url = "https://fr.wiktionary.org/w/api.php?action=parse&page=#{word}&prop=wikitext&format=json&redirects=1"
          raw = URI.parse(url).open(read_timeout: 5, "User-Agent" => "motus-kawaii/1.0 (terminal)") do |f|
            JSON.parse(f.read)
          end
          wt = raw.dig("parse", "wikitext", "*").to_s
          # bloc langue française uniquement
          fr = wt.split(/^==\s*\{\{langue\|([^}]+)\}\}\s*==/)[1..] || []
          block = fr.each_slice(2).to_h["fr"] || ""
          defs = block.lines.select { |l| l.start_with?("# ") && !l.start_with?("#*") }
          defs = wt.lines.select { |l| l.start_with?("# ") } if defs.empty?
          defs.map { |l| clean_wikitext(l.sub(/^#\s*/, "")) }.reject(&:empty?).uniq
        rescue StandardError
          []
        end
      text = if defs && !defs.empty?
               defs.first(2).map { |d| "• #{d}" }.join("\n")
             else
               "définition non trouvée pour « #{word} »"
             end
      @definition = "« #{word} »\n#{text}"
    end
  end

  def clean_wikitext(s)
    s = s.gsub(/\{\{[-_ ]*de \|(?:[^|]+\|)*([^}|]+)(?:\|[^}]*)?\}\}/i, '\1') # {{de|craner}}
    s = s.gsub(/\{\{(?:cf|voir)\|[^}]*\}\}/i, "")
    s = s.gsub(/\[\[([^\]|]+\|)?([^\]]+)\]\]/, '\2')                          # [[lien|texte]]
    s = s.gsub(/'+/, "")                                                     # italiques
    s = s.gsub(/\{\{[^}]*\}\}/, "").gsub(/<[^>]+>/, "").squeeze(" ").strip
  end

  # ── soumission ──

  def submit
    word = @current.map { |c| c || "·" }.join
    if word.include?("·")
      @message = "Le mot n'est pas complet... (･_･;"
      return
    end
    unless valid_word?(word)
      @message = "#{word} n'est pas dans mon dictionnaire... (＞﹏＜)"
      return
    end

    fb = score(word)
    @tries << [word, fb]
    @states << fb

    if word == @secret
      @over = true
      @won = true
      @message = "GAGNÉ ! #{MAX_TRIES - @tries.size + 1} essai(s) d'avance ☆*:.｡.o(≧▽≦)o.｡.:*☆"
      fetch_definition(@secret)
      return
    end

    if @tries.size >= MAX_TRIES
      @over = true
      @won = false
      @message = "Perdu ! Le mot était #{@secret.upcase} (´；ω；`)"
      fetch_definition(@secret)
      return
    end

    # report des lettres bien placées + révélation d'une lettre de plus
    @locked = fb.map { |f| f == :good }
    @current = Array.new(@len) do |i|
      fb[i] == :good ? @secret[i] : nil
    end
    if @revealed < @len - 1
      @revealed += 1
      i = @revealed
      unless @current[i]
        @current[i] = @secret[i]
      end
    end
    @cursor = next_free(0, +1)
    @message = "Raté ! Une lettre en plus... ♪"
  end

  # ── vue ──

  def view
    @menu ? center(menu_view) : center(game_view)
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

  def game_view
    b = +""
    b << TITLE_STYLE.render(" ♡  M O T U S  ♡ ")
    b << "\n"
    b << PLAIN_S.render("mot de #{@len} lettres · essai #{@tries.size + 1}/#{MAX_TRIES}")
    b << "\n\n"

    # grille complète : 6 lignes × N lettres, toujours visible
    MAX_TRIES.times do |row|
      played = row < @tries.size
      is_current = row == @tries.size && !@over
      line = (0...@len).map do |col|
        if played
          c = @tries[row][0][col]
          st = @states[row][col]
          case st
          when :good then GOOD_STYLE.render(c)
          when :present then PRES_STYLE.render(c)
          else MISS_STYLE.render(c)
          end
        elsif is_current
          ch = @current[col] || (col.zero? ? @secret[0] : nil)
          ch = @secret[0] if col.zero?
          if @locked[col]
            GIVEN_STYLE.render(ch)
          elsif ch
            col == @cursor ? CURSOR_STYLE.render(ch) : TYPING_STYLE.render(ch)
          elsif col == @cursor
            CURSOR_STYLE.render("_")
          else
            MUTED_S.render("·")
          end
        else
          MUTED_S.render("·")
        end
      end.join
      b << line << "\n"
    end

    b << "\n"
    if @over
      b << (@won ? WIN_STYLE : LOSE_STYLE).render(@message) << "\n"
      b << PAW_STYLE.render("🐾 ♡ 🐾 ♡ 🐾 ♡") << "\n" if @won
      if @definition
        b << "\n"
        b << DEF_TITLE.render("📖 Définition") << "\n"
        b << DEF_STYLE.render(@definition) << "\n"
      end
      b << "\n"
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
