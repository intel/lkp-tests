LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

module LKP
  # Tracks per-sibling-cgroup stats for a suite whose run script emits an
  # "Instance: N" marker line (see lib/run.sh's echo_instance) ahead of
  # each instance's output, for a cgroup2/nr_instances job that gives
  # sibling cgroups asymmetric demand via a "<param>_by_instance" override
  # (see lib/run.sh's instance_override). A plain single-instance run only
  # ever populates instance 1, so #many? is the guard a parse script uses
  # to skip emitting per-instance stats when there is nothing beyond the
  # combined view to add.
  class PerInstance
    INSTANCE_LINE = /^Instance: (\d+)/

    def initialize(&)
      @instance = 1
      @stats = Hash.new(&)
    end

    # Updates the current instance from a line if it is an "Instance: N"
    # marker, otherwise leaves it unchanged. Returns true if the line was
    # consumed as a marker, so a caller's line dispatch can skip it.
    def scan(line)
      m = INSTANCE_LINE.match(line)
      return false unless m

      @instance = m[1].to_i
      true
    end

    def current
      @stats[@instance]
    end

    def many?
      @stats.size > 1
    end

    def each_sorted(&)
      @stats.sort.each(&)
    end
  end
end
