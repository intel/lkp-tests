require 'spec_helper'
require "#{LKP_SRC}/lib/yaml"

# programs/blktests/include is rendered per job with ___ bound to the job's
# blktests params, so each example renders it for one job shape.
describe 'programs/blktests/include' do
  def needed_kconfigs(params)
    include_file = "#{LKP_SRC}/programs/blktests/include"

    load_yaml(include_file, { '___' => params })['need_kconfig'].map do |entry|
      entry.is_a?(Hash) ? entry.keys.first : entry.to_s.split(':').first
    end
  end

  # nvme_trtype is only set by nvme jobs: ___.nvme_trtype would raise KeyError
  # for the other jobs and the include would then be dropped, losing every
  # kconfig it lists.
  it 'keeps its kconfigs for a job that does not set nvme_trtype' do
    kconfigs = needed_kconfigs({ 'test' => 'block-001' })

    expect(kconfigs).to include('BLK_DEV_LOOP', 'BLK_DEV_UBLK')
  end

  %w[loop tcp].each do |trtype|
    it "needs no soft-RDMA driver for nvme over #{trtype}" do
      kconfigs = needed_kconfigs({ 'test' => 'nvme-050', 'nvme_trtype' => trtype })

      expect(kconfigs).not_to include('RDMA_RXE', 'RDMA_SIW')
    end
  end

  it 'needs rxe for nvme over rdma when use_siw is not set' do
    kconfigs = needed_kconfigs({ 'test' => 'nvme-050', 'nvme_trtype' => 'rdma' })

    expect(kconfigs).to include('RDMA_RXE')
    expect(kconfigs).not_to include('RDMA_SIW')
  end

  it 'needs rxe for nvme over rdma when use_siw is false' do
    kconfigs = needed_kconfigs({ 'test' => 'nvme-050', 'nvme_trtype' => 'rdma', 'use_siw' => false })

    expect(kconfigs).to include('RDMA_RXE')
    expect(kconfigs).not_to include('RDMA_SIW')
  end

  [true, 'true'].each do |use_siw|
    it "needs siw for nvme over rdma when use_siw is #{use_siw.inspect}" do
      kconfigs = needed_kconfigs({ 'test' => 'nvme-group-00', 'nvme_trtype' => 'rdma', 'use_siw' => use_siw })

      expect(kconfigs).to include('RDMA_SIW')
      expect(kconfigs).not_to include('RDMA_RXE')
    end
  end

  it 'needs rxe for srp, which has no nvme_trtype' do
    kconfigs = needed_kconfigs({ 'test' => 'srp-014' })

    expect(kconfigs).to include('RDMA_RXE')
  end
end
