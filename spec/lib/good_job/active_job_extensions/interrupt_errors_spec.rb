# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::InterruptErrors do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::InterruptErrors

      def perform
      end
    end)
  end

  context 'when a dequeued job has a performed_at but no finished_at' do
    before do
      active_job = TestJob.perform_later
      good_job = GoodJob::Job.find_by(active_job_id: active_job.job_id)
      good_job.update!(performed_at: Time.current, finished_at: nil)
      good_job.discrete_executions.create!(performed_at: Time.current, finished_at: nil)
    end

    it 'raises a GoodJob::InterruptError' do
      expect { GoodJob.perform_inline }.to raise_error(GoodJob::InterruptError)
      expect(GoodJob::Job.last).to have_attributes(
        error: start_with('GoodJob::InterruptError: Interrupted after starting perform at'),
        error_event: GoodJob::Job::ERROR_EVENT_INTERRUPTED
      )
    end

    context 'when discrete execution is NOT enabled' do
      before do
        allow(GoodJob::Execution).to receive(:discrete_support?).and_return(false)
      end

      it 'is rescuable' do
        TestJob.retry_on GoodJob::InterruptError

        expect { GoodJob.perform_inline }.not_to raise_error
        expect(GoodJob::Execution.count).to eq(2)

        job = GoodJob::Job.first
        expect(job.executions.order(created_at: :asc).to_a).to contain_exactly(have_attributes(
                                                                                 performed_at: be_present,
                                                                                 finished_at: be_present,
                                                                                 error: start_with('GoodJob::InterruptError: Interrupted after starting perform at'),
                                                                                 error_event: GoodJob::Job::ERROR_EVENT_RETRIED
                                                                               ), have_attributes(
                                                                                    performed_at: nil,
                                                                                    finished_at: nil,
                                                                                    error: nil,
                                                                                    error_event: nil
                                                                                  ))
      end
    end

    context 'when discrete execution is enabled' do
      before do
        allow(GoodJob::Execution).to receive(:discrete_support?).and_return(true)
      end

      it 'does not create a new execution' do
        TestJob.retry_on GoodJob::InterruptError

        expect { GoodJob.perform_inline }.not_to raise_error
        expect(GoodJob::Job.count).to eq(1)
        expect(GoodJob::Execution.count).to eq(1)
        expect(GoodJob::DiscreteExecution.count).to eq(2)

        job = GoodJob::Job.first
        expect(job.executions.count).to eq(1)
        expect(job.discrete_executions.count).to eq(2)
        expect(job).to have_attributes(
          performed_at: be_blank,
          finished_at: be_blank,
          error: start_with('GoodJob::InterruptError: Interrupted after starting perform at'),
          error_event: GoodJob::Job::ERROR_EVENT_RETRIED
        )

        initial_discrete_execution = job.discrete_executions.first
        expect(initial_discrete_execution).to have_attributes(
          performed_at: be_present,
          finished_at: be_present,
          error: start_with('GoodJob::InterruptError: Interrupted after starting perform at'),
          error_event: GoodJob::Job::ERROR_EVENT_INTERRUPTED
        )

        retried_discrete_execution = job.discrete_executions.last
        expect(retried_discrete_execution).to have_attributes(
          performed_at: be_present,
          finished_at: be_present,
          error: start_with('GoodJob::InterruptError: Interrupted after starting perform at'),
          error_event: GoodJob::Job::ERROR_EVENT_RETRIED
        )
      end
    end
  end

  context 'when dequeued job does not have performed at' do
    before do
      TestJob.perform_later
    end

    it 'does not raise' do
      expect { GoodJob.perform_inline }.not_to raise_error
    end
  end
end
