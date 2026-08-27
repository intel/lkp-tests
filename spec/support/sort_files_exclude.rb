require "#{LKP_SRC}/lib/lkp_pattern"

# etc/sort-files-exclude is the single shared exclusion list, kept in
# sync with tools/sort-files, spec/unit/lib/file_sorting_spec.rb, and
# spec/unit/require_order_spec.rb so the check and the tool that
# (re)sorts files never drift apart on what's exempt.
SORT_EXCLUDE_ENTRIES = LKP::Pattern.lines("#{LKP_SRC}/etc/sort-files-exclude").freeze

def path_excluded?(file)
  relative = file.delete_prefix("#{LKP_SRC}/")

  SORT_EXCLUDE_ENTRIES.any? do |entry|
    entry.end_with?('/') ? relative.include?("/#{entry}") || relative.start_with?(entry) : relative == entry
  end
end
