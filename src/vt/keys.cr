module Term::VT
  module Keys
    SEQUENCES = {
      :enter     => "\r",
      :tab       => "\t",
      :escape    => "\e",
      :backspace => "\u{7f}",
      :up        => "\e[A",
      :down      => "\e[B",
      :right     => "\e[C",
      :left      => "\e[D",
      :home      => "\e[H",
      :end       => "\e[F",
      :page_up   => "\e[5~",
      :page_down => "\e[6~",
      :f1        => "\eOP",
      :f2        => "\eOQ",
      :f3        => "\eOR",
      :f4        => "\eOS",
      :f5        => "\e[15~",
      :f6        => "\e[17~",
      :f7        => "\e[18~",
      :f8        => "\e[19~",
      :f9        => "\e[20~",
      :f10       => "\e[21~",
      :f11       => "\e[23~",
      :f12       => "\e[24~",
      :ctrl_a    => "\u{1}",
      :ctrl_b    => "\u{2}",
      :ctrl_c    => "\u{3}",
      :ctrl_d    => "\u{4}",
      :ctrl_e    => "\u{5}",
      :ctrl_f    => "\u{6}",
      :ctrl_g    => "\u{7}",
      :ctrl_h    => "\u{8}",
      :ctrl_i    => "\u{9}",
      :ctrl_j    => "\u{a}",
      :ctrl_k    => "\u{b}",
      :ctrl_l    => "\u{c}",
      :ctrl_m    => "\u{d}",
      :ctrl_n    => "\u{e}",
      :ctrl_o    => "\u{f}",
      :ctrl_p    => "\u{10}",
      :ctrl_q    => "\u{11}",
      :ctrl_r    => "\u{12}",
      :ctrl_s    => "\u{13}",
      :ctrl_t    => "\u{14}",
      :ctrl_u    => "\u{15}",
      :ctrl_v    => "\u{16}",
      :ctrl_w    => "\u{17}",
      :ctrl_x    => "\u{18}",
      :ctrl_y    => "\u{19}",
      :ctrl_z    => "\u{1a}",
    }

    def self.sequence(name : Symbol) : String
      SEQUENCES[name]? || raise ArgumentError.new("unknown key: #{name}")
    end

    def self.supported : Array(Symbol)
      SEQUENCES.keys.sort_by(&.to_s)
    end
  end
end
