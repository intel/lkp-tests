require 'spec_helper'
require "#{LKP_SRC}/lib/test_result_classifier"

describe TestResultClassifier do
  before(:all) do
    @test_result_classifier = described_class.new('pass' => { '*' => 'pass' }, 'fail' => { '*' => 'fail', 't' => 'crash crashed' },
                                                  'skip' => { '*' => 'skip block' }, 'skipped' => { '*' => 'skipped' })
  end

  describe '.initialize' do
    it 'defines singleton methods' do
      expect(@test_result_classifier).to respond_to(:pass?)
      expect(@test_result_classifier).to respond_to(:skipped?)

      expect(described_class.new({})).not_to respond_to(:pass?)
    end
  end

  describe '.pass?' do
    context 'when given passed stat' do
      it 'returns true' do
        expect(@test_result_classifier).to be_pass('s.x.pass')
        expect(@test_result_classifier).to be_pass('s.x.y.pass')
        expect(@test_result_classifier).to be_pass('t.x.pass')
        expect(@test_result_classifier).to be_pass('t.x.PaSS')
        expect(@test_result_classifier).to be_pass('t.pass')
      end
    end

    context 'when given non passed stat' do
      it 'returns false' do
        expect(@test_result_classifier).not_to be_pass('s.x.passed')
        expect(@test_result_classifier).not_to be_pass('t.x.failed')
        expect(@test_result_classifier).not_to be_pass('....pass')
      end
    end
  end

  describe '.fail?' do
    context 'when given failed stat' do
      it 'returns true' do
        expect(@test_result_classifier).to be_fail('s.x.fail')
        expect(@test_result_classifier).to be_fail('t.x.crash')
      end
    end

    context 'when given non failed stat' do
      it 'returns false' do
        expect(@test_result_classifier).not_to be_fail('s.x.failed')
        expect(@test_result_classifier).not_to be_fail('s.x.crash')
      end
    end
  end

  describe '.skip?' do
    context 'when given skipped stat' do
      it 'returns true' do
        expect(@test_result_classifier).to be_skip('s.x.block')
      end
    end

    context 'when given non skipped stat' do
      it 'returns false' do
        expect(@test_result_classifier).not_to be_skip('s.block.failed')
        expect(@test_result_classifier).not_to be_skip('s.x.skipped')
      end
    end
  end

  describe '.result?' do
    context 'when given a valid stat' do
      it 'returns true' do
        expect(@test_result_classifier).to be_result('s.x.BLOCK')
        expect(@test_result_classifier).to be_result('s.x.y.z.pass')
        expect(@test_result_classifier).to be_result('s.x_y-z.skipped')
      end
    end

    context 'when given an invalid stat' do
      it 'returns false' do
        expect(@test_result_classifier).not_to be_result('s.block.error')
        expect(@test_result_classifier).not_to be_result('....pass')
      end
    end
  end
end
